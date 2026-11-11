// Pumping, settling, auditing and bookkeeping for test/a11y/screens_a11y_test.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_a11y_test/flutter_a11y_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/src/data/service/navigation_service.dart';
import 'package:wallet/src/domain/usecase/uri/decode_uri_usecase.dart';
import 'package:wallet/src/domain/usecase/wallet/setup_mocked_wallet_usecase.dart';
import 'package:wallet/src/navigation/wallet_routes.dart';
import 'package:wallet/src/wallet_constants.dart';
import 'package:wallet_core/core.dart' as core;

import 'a11y_app.dart';

/// Phone viewport every screen starts from (logical px, DPR 3), the same as
/// flutter-a11y's tool/score_realapps_runtime.
const Size kPhoneSize = Size(412, 915);
const double kPhoneDpr = 3;

/// Upper bound when the view is grown to lay out a whole scrolling screen.
const double kMaxViewHeight = 8000;

/// Where the per-screen log is written, next to the findings the sink writes.
const String kScreensFile = '.a11y/flutter/runtime-screens.json';

/// Findings are attributed to the app's own widgets, never to the harness.
A11yAuditConfig get auditConfig => A11yAuditConfig(
  platform: null,
  reflow: true,
  sourceRoots: ['${Directory.current.path}/lib/'],
);

/// The wallet a test starts with.
enum Wallet {
  /// A freshly installed app: no PIN, no cards.
  fresh,

  /// The mock flavour's demo wallet (the app's own `SetupMockedWalletUseCase`, which its
  /// introduction screen offers as "Skip Setup" in debug mock builds): PIN set, unlocked,
  /// the mock PID and address cards issued, with their history.
  ready,
}

/// A running app.
class Shell {
  Shell(this.tester, this.navigatorKey);

  final WidgetTester tester;
  final GlobalKey<NavigatorState> navigatorKey;

  NavigatorState get navigator => navigatorKey.currentState!;

  /// A context below every app-level provider (use cases, repositories, services).
  BuildContext get context => navigatorKey.currentContext!;

  T read<T>() => context.read<T>();

  /// Pushes a route of the app's route table and lets it load.
  Future<void> push(String route, {Object? arguments}) async {
    unawaited(navigator.pushNamed(route, arguments: arguments));
    await settle(tester);
  }

  /// Opens one of the mock flavour's deeplink scenarios (README, "Deeplink Scenarios"),
  /// e.g. `{"id":"BAR","type":"verify"}`.
  ///
  /// This does what the app's `DeeplinkService` does with a link from the operating
  /// system: decode it with `DecodeUriUseCase`, hand the result to `NavigationService`.
  /// The service itself cannot be fed from a test: the `AppLinks` plugin facade is a
  /// singleton that subscribes to the platform stream once, in the zone of the first
  /// test, and a finished test's fake-async zone never runs its callbacks again.
  Future<void> openDeeplink(String scenario) async {
    final uri = Uri.parse('$kDeeplinkScheme://$kDeeplinkHost#${Uri.encodeComponent(scenario)}');
    final request = await run(read<DecodeUriUseCase>().invoke(uri));
    if (request.hasError) throw StateError('deeplink not decoded: ${request.error}');
    unawaited(read<NavigationService>().handleNavigationRequest(request.value!, queueIfNotReady: true));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await settle(tester);
  }

  /// Name of the route on top of the navigator (null for a dialog, a bottom sheet or a
  /// screen the app pushes without a name), and of the nearest named route under it.
  ///
  /// Read from the widget tree: every route builds a `_ModalScopeStatus` holding itself,
  /// in stack order. (`Navigator.popUntil` is the usual way to look at the stack, but its
  /// predicate has to answer true for the top route or that route is popped.)
  ({String? top, String? named}) get routes {
    final stack = <Route<dynamic>>[
      for (final element
          in find.byWidgetPredicate((w) => '${w.runtimeType}' == '_ModalScopeStatus', skipOffstage: false).evaluate())
        // ignore: avoid_dynamic_calls
        (element.widget as dynamic).route as Route<dynamic>,
    ];
    if (stack.isEmpty) return (top: null, named: null);
    final named = stack.reversed.map((route) => route.settings.name).firstWhere((n) => n != null, orElse: () => null);
    return (top: stack.last.settings.name, named: named);
  }

  /// Awaits [future] (app code that waits on the mock core's timers) on the fake clock.
  Future<T> run<T>(Future<T> future) => drive(tester, future);
}

/// Per-isolate log of screens, written by [ScreenLog.flush].
abstract final class ScreenLog {
  static final Map<String, Map<String, Object?>> _screens = {};

  static void audited(String id, A11yAuditResult result, Map<String, Object?> meta) {
    _screens[id] = {
      'status': 'audited',
      'findingCount': result.findings.length,
      'ruleIds': result.ruleIds,
      'needsReview': result.needsReview.length,
      if (result.diagnostics.isNotEmpty) 'diagnostics': [for (final d in result.diagnostics) d.id]..sort(),
      ...meta,
    };
  }

  static void notAudited(String id, String status, String reason, [Map<String, Object?> meta = const {}]) {
    _screens[id] = {'status': status, 'reason': reason, ...meta};
  }

  static Map<String, Object?>? of(String id) => _screens[id];

  static Iterable<MapEntry<String, Map<String, Object?>>> get entries => _screens.entries;

  /// Extra top-level entries of the log (the route coverage).
  static final Map<String, Object?> summary = {};

  static void flush() {
    if (_screens.isEmpty) return;
    final ids = _screens.keys.toList()..sort();
    final file = File(kScreensFile)..parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({
        'mockFlavour': kMockFlavour,
        'viewport': '${kPhoneSize.width.toInt()}x${kPhoneSize.height.toInt()}@${kPhoneDpr.toInt()}',
        'channelsTouched': touchedChannels.toList()..sort(),
        ...summary,
        'screens': {for (final id in ids) id: _screens[id]},
      })}\n',
    );
  }
}

String _firstLine(Object e) => '$e'.split('\n').first.trim().replaceAll(RegExp('#[0-9a-f]{5}'), '#_');

/// First line of every exception pending in [tester], drained (hash codes removed so the
/// log is deterministic).
List<String> takeExceptions(WidgetTester tester) {
  final out = <String>[];
  for (Object? e = tester.takeException(); e != null; e = tester.takeException()) {
    out.add(_firstLine(e));
  }
  return out;
}

/// Lets real asynchronous work finish (asset loads, image and SVG decoding run outside
/// the fake clock), interleaved with frames, then lets fake-clock timers and transitions
/// end. Bounded: the app has animations that never end (progress indicators), which is
/// why this is not `pumpAndSettle`.
Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await _precacheImages(tester);
  for (var i = 0; i < 30 && tester.binding.hasScheduledFrame; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The same thing the app's own `pumpWidgetWithAppWrapper` does before a golden is taken:
/// asset images decode on a real isolate, so without this they are still blank.
Future<void> _precacheImages(WidgetTester tester) async {
  final images = find.byType(Image, skipOffstage: false).evaluate().toList();
  final boxes = find.byType(DecoratedBox, skipOffstage: false).evaluate().toList();
  await tester.runAsync(() async {
    for (final element in images) {
      if (!element.mounted) continue;
      await precacheImage((element.widget as Image).image, element, onError: (_, _) {});
    }
    for (final element in boxes) {
      if (!element.mounted) continue;
      final decoration = (element.widget as DecoratedBox).decoration;
      final image = decoration is BoxDecoration ? decoration.image : null;
      if (image != null) await precacheImage(image.image, element, onError: (_, _) {});
    }
  });
  await tester.pump();
}

/// Awaits [future] while advancing the fake clock, for app and mock-core code that waits
/// on `Future.delayed`.
Future<T> drive<T>(WidgetTester tester, Future<T> future, {Duration limit = const Duration(seconds: 30)}) async {
  var done = false;
  late T value;
  Object? error;
  StackTrace? stack;
  unawaited(
    future.then<void>(
      (v) {
        value = v;
        done = true;
      },
      onError: (Object e, StackTrace s) {
        error = e;
        stack = s;
        done = true;
      },
    ),
  );
  const step = Duration(milliseconds: 100);
  for (var waited = Duration.zero; !done && waited < limit; waited += step) {
    await tester.pump(step);
  }
  if (error != null) Error.throwWithStackTrace(error!, stack!);
  if (!done) throw TimeoutException('not finished after $limit of fake time');
  return value;
}

/// Starts the app the way a cold start does and waits for the first real screen.
Future<Shell> launch(WidgetTester tester, {Wallet wallet = Wallet.ready, bool permissionsGranted = false}) async {
  tester.view.devicePixelRatio = kPhoneDpr;
  tester.view.physicalSize = kPhoneSize * kPhoneDpr;
  addTearDown(tester.view.reset);

  initMockCore();
  installPlatformFakes(tester, permissionsGranted: permissionsGranted);
  // The mock core is a set of isolate-wide singletons: end whatever session the previous
  // test left open and wipe the wallet, so every test starts from the same state.
  await drive(tester, core.cancelSession());
  await drive(tester, core.resetWallet());
  await drive(tester, core.postInit());

  final shell = Shell(tester, GlobalKey<NavigatorState>());
  await tester.pumpWidget(A11yWalletApp(navigatorKey: shell.navigatorKey));
  await settle(tester);

  if (wallet == Wallet.ready) {
    // What the introduction screen's "Skip Setup" button does (introduction_screen.dart).
    await shell.run(shell.read<SetupMockedWalletUseCase>().invoke());
    unawaited(shell.navigator.pushReplacementNamed(WalletRoutes.dashboardRoute));
    await settle(tester);
  }
  return shell;
}

/// One step of a [journey]: a line of the small step language below, or a function for
/// what the language cannot say (a route that takes an argument object).
///
/// - `audit <screen id>`: audit what is on screen (`audit! <id>` keeps the phone viewport)
/// - `tap <text>`: tap the first widget showing exactly that text (else containing it)
/// - `sem <label>`: tap the first widget with that semantics label
/// - `push <route>`: push a route of the app's route table that takes no argument
/// - `link <json>`: open one of the mock flavour's deeplink scenarios
/// - `pin <digits>`: type on the app's PIN keyboard
/// - `wait <seconds>`: let that much time pass in the app
/// - `back`: the system back gesture
/// - `lock`: lock the wallet, as the app does when it goes to the background
typedef Step = Object;

/// Runs [steps] against a freshly started app. A step that fails ends the journey: every
/// `audit` after it is recorded as not audited, with the failing step and what was on
/// screen, and the run goes on with the next journey.
Future<void> journey(
  WidgetTester tester,
  List<Step> steps, {
  Wallet wallet = Wallet.ready,
  bool permissionsGranted = false,
}) async {
  await guarded(tester, () async {
    final shell = await launch(tester, wallet: wallet, permissionsGranted: permissionsGranted);
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      try {
        if (step is Future<void> Function(Shell)) {
          await step(shell);
          await settle(tester);
        } else {
          await _runStep(shell, step as String);
        }
      } catch (e) {
        final what = step is String ? step : 'step ${i + 1}';
        final reason = '"$what" failed: ${_firstLine(e)}';
        final seen = describeScreen(tester);
        // ignore: avoid_print
        print('a11y journey stopped: $reason\n$seen');
        for (final later in steps.skip(i).whereType<String>().where((s) => s.startsWith('audit'))) {
          ScreenLog.notAudited(later.substring(later.indexOf(' ') + 1), 'failed', reason);
        }
        takeExceptions(tester);
        return;
      }
    }
  });
}

Future<void> _runStep(Shell shell, String step) async {
  final tester = shell.tester;
  final space = step.indexOf(' ');
  final op = space < 0 ? step : step.substring(0, space);
  final arg = space < 0 ? '' : step.substring(space + 1);
  switch (op) {
    case 'audit' || 'audit!':
      final routes = shell.routes;
      await audit(
        tester,
        arg,
        route: routes.top,
        over: routes.top == null ? routes.named : null,
        grow: op == 'audit',
      );
    case 'tap':
      await tapText(tester, arg);
    case 'sem':
      await tapSemantics(tester, arg);
    case 'push':
      await shell.push(arg);
    case 'link':
      await shell.openDeeplink(arg);
    case 'pin':
      await enterPin(tester, arg);
    case 'wait':
      for (var i = 0; i < int.parse(arg) * 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await settle(tester);
    case 'back':
      await tester.binding.handlePopRoute();
      await settle(tester);
    case 'lock':
      await shell.run(core.lockWallet());
      await settle(tester);
    default:
      throw ArgumentError('unknown step "$step"');
  }
}

/// Largest distance any on-screen vertical scrollable can still scroll.
double _remainingScroll(WidgetTester tester) {
  var extent = 0.0;
  for (final element in find.byType(Scrollable).evaluate()) {
    final state = (element as StatefulElement).state as ScrollableState;
    final position = state.position;
    if (position.axis != Axis.vertical || !position.hasContentDimensions) continue;
    extent = math.max(extent, position.maxScrollExtent - position.pixels);
  }
  return extent;
}

/// Audits what is on screen under [screenId] and records it. Never throws: a failure is
/// recorded on the screen.
///
/// The view is first grown until the screen's vertical scrollables have nothing left to
/// scroll (or [kMaxViewHeight]), so content below the fold is laid out, has semantics and
/// is audited as if scrolled through; [grow] false keeps the phone viewport, for screens
/// whose layout is the viewport (a camera preview, a full-screen video).
Future<A11yAuditResult?> audit(
  WidgetTester tester,
  String screenId, {
  String? route,
  String? over,
  bool grow = true,
}) async {
  final meta = <String, Object?>{'route': ?route, 'over': ?over};
  try {
    await settle(tester);
    final exceptions = takeExceptions(tester);

    var height = kPhoneSize.height;
    if (grow) {
      for (var i = 0; i < 8; i++) {
        final extent = _remainingScroll(tester);
        if (extent < 1 || height >= kMaxViewHeight) break;
        height = math.min(kMaxViewHeight, height + extent).ceilToDouble();
        tester.view.physicalSize = Size(kPhoneSize.width, height) * kPhoneDpr;
        await tester.pump();
        await settle(tester, rounds: 2);
      }
    }
    final remaining = _remainingScroll(tester);
    exceptions.addAll(takeExceptions(tester));

    await _screenshot(tester, screenId);
    final result = await auditScreen(tester, screenId: screenId, config: auditConfig);
    exceptions.addAll(takeExceptions(tester));
    ScreenLog.audited(screenId, result, {
      ...meta,
      'viewport': '${kPhoneSize.width.toInt()}x${height.toInt()}@${kPhoneDpr.toInt()}',
      if (remaining >= 1) 'remainingScrollPx': remaining.round(),
      if (exceptions.isNotEmpty) 'exceptions': exceptions,
    });
    // ignore: avoid_print
    print(
      'a11y $screenId: ${result.findings.length} finding(s)'
      '${exceptions.isEmpty ? '' : ', ${exceptions.length} exception(s)'}',
    );
    tester.view.physicalSize = kPhoneSize * kPhoneDpr;
    await tester.pump();
    return result;
  } catch (e) {
    ScreenLog.notAudited(screenId, 'failed', _firstLine(e), meta);
    // ignore: avoid_print
    print('a11y $screenId: NOT AUDITED: ${_firstLine(e)}');
    takeExceptions(tester);
    return null;
  }
}

/// With `A11Y_SCREENSHOTS=<directory>` in the environment, writes a PNG of each screen as
/// it is audited (at 1 px per logical px), for the people who label the findings.
Future<void> _screenshot(WidgetTester tester, String screenId) async {
  final directory = Platform.environment['A11Y_SCREENSHOTS'];
  if (directory == null || directory.isEmpty) return;
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  final size = view.size;
  await tester.runAsync(() async {
    final image = await layer.toImage(Offset.zero & (size * kPhoneDpr), pixelRatio: 1 / kPhoneDpr);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$directory/${screenId.replaceAll('/', '__')}.png')..parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Runs [body] so that an uncaught asynchronous error of the app is recorded on the
/// screens audited in this test instead of ending the run, and takes the app down at the
/// end so no timer of it outlives the test.
Future<void> guarded(WidgetTester tester, Future<void> Function() body) async {
  final before = ScreenLog._screens.keys.toSet();
  final asyncErrors = <String>[];
  final done = Completer<void>();
  String? failure;
  // ignore: unawaited_futures, the zone's body reports through [done]
  runZonedGuarded(
    () async {
      try {
        await body();
      } catch (e) {
        failure = _firstLine(e);
      } finally {
        try {
          await tester.pumpWidget(const SizedBox.shrink());
          await settle(tester, rounds: 2);
          await tester.pump(const Duration(seconds: 5));
          takeExceptions(tester);
        } finally {
          if (!done.isCompleted) done.complete();
        }
      }
    },
    (e, _) => asyncErrors.add(_firstLine(e)),
  );
  await done.future;
  final mine = ScreenLog._screens.keys.toSet().difference(before);
  for (final id in mine) {
    if (asyncErrors.isNotEmpty) ScreenLog._screens[id]!['asyncErrors'] = asyncErrors.toSet().toList()..sort();
    if (failure != null) ScreenLog._screens[id]!['testFailure'] = failure;
  }
  if (failure != null) {
    // ignore: avoid_print
    print('a11y test body stopped: $failure');
    pendingFailures.add(failure!);
  }
}

/// Failures of a test body after its last audit (navigation to the next step did not
/// work). They are reported by the coverage test at the end, not swallowed.
final List<String> pendingFailures = <String>[];

/// Waits for [find] to match something: lets pending loads finish, then scrolls the
/// screen's main list down a page at a time, as a user looking for a button would.
Future<void> _lookFor(WidgetTester tester, Finder Function() target) async {
  for (var i = 0; i < 6 && target().evaluate().isEmpty; i++) {
    await settle(tester, rounds: 3);
  }
  for (var i = 0; i < 12 && target().evaluate().isEmpty; i++) {
    ScrollPosition? furthest;
    for (final element in tester.elementList(find.byType(Scrollable))) {
      final position = ((element as StatefulElement).state as ScrollableState).position;
      if (position.axis != Axis.vertical || !position.hasContentDimensions) continue;
      if (furthest == null || position.extentAfter > furthest.extentAfter) furthest = position;
    }
    if (furthest == null || furthest.extentAfter < 1) break;
    furthest.jumpTo(math.min(furthest.maxScrollExtent, furthest.pixels + 400));
    await tester.pump(const Duration(milliseconds: 100));
    await settle(tester, rounds: 1);
  }
}

Future<void> _tap(WidgetTester tester, Finder Function() find, String what, int index) async {
  await _lookFor(tester, find);
  final all = find();
  if (all.evaluate().isEmpty) throw StateError('nothing with $what on screen');
  await tester.ensureVisible(all.at(index));
  await tester.pump(const Duration(milliseconds: 300));
  // Prefer what can actually be hit: a page kept alive under the current one can show
  // the same text.
  final hittable = find().hitTestable();
  final target = hittable.evaluate().length > index ? hittable.at(index) : find().at(index);
  await tester.tap(target, warnIfMissed: false);
  await settle(tester);
}

/// Taps the first widget showing exactly [text] (else containing it), scrolling to it
/// first, and lets the app react.
Future<void> tapText(WidgetTester tester, String text, {int index = 0}) {
  Finder find_() {
    final exact = find.text(text, findRichText: true);
    return exact.evaluate().isNotEmpty ? exact : find.textContaining(text, findRichText: true);
  }

  return _tap(tester, find_, 'text "$text"', index);
}

/// Taps the first widget whose semantics label starts with [label].
Future<void> tapSemantics(WidgetTester tester, String label, {int index = 0}) {
  final pattern = RegExp('^${RegExp.escape(label)}');
  return _tap(tester, () => find.bySemanticsLabel(pattern), 'semantics label "$label"', index);
}

/// Types [pin] on the app's own PIN keyboard and waits for the mock core to check it.
Future<void> enterPin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.byKey(Key('keyboardDigitKey#$digit')).hitTestable().first);
    await tester.pump(const Duration(milliseconds: 50));
  }
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await settle(tester);
}

/// Labels of what is on screen, for working out a flow: every visible text, and every
/// semantics node with a tap action.
String describeScreen(WidgetTester tester) {
  final texts = <String>[];
  for (final element in find.byType(Text).hitTestable().evaluate()) {
    final widget = element.widget as Text;
    final value = widget.data ?? widget.textSpan?.toPlainText() ?? '';
    if (value.trim().isNotEmpty) texts.add(value.replaceAll('\n', ' / '));
  }
  final tappable = <String>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.hasAction(ui.SemanticsAction.tap) && !data.flagsCollection.isHidden) {
      tappable.add(data.label.isEmpty ? '<${data.tooltip}|${data.value}>' : data.label.replaceAll('\n', ' / '));
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  final root = tester.binding.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;
  if (root != null) visit(root);
  return 'TEXT: ${texts.join(' | ')}\nTAP: ${tappable.join(' | ')}';
}
