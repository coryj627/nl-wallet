// The app shell the accessibility audit pumps: the widget tree of lib/main.dart's
// `mainImpl()` over the app's own in-memory mock core (packages/wallet_mock), i.e. the
// "mock" flavour described in the README, with nothing replaced inside the app.
//
// The only substitutions are at the edge of the Dart code, where a device would answer:
// plugin platform interfaces and platform channels (see [installPlatformFakes]).
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:app_links_platform_interface/app_links_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet/src/di/wallet_dependency_provider.dart';
import 'package:wallet/src/feature/common/widget/flutter_app_configuration_provider.dart';
import 'package:wallet/src/feature/common/widget/privacy_cover.dart';
import 'package:wallet/src/feature/configuration/config_expiry_checker.dart';
import 'package:wallet/src/feature/lock/auto_lock_observer.dart';
import 'package:wallet/src/feature/maintenance/maintenance_checker.dart';
import 'package:wallet/src/feature/root/root_checker.dart';
import 'package:wallet/src/feature/update/update_checker.dart';
import 'package:wallet/src/wallet_app.dart';
import 'package:wallet_core/core.dart' as core;
import 'package:wallet_mock/mock.dart' as mock;
import 'package:workmanager/workmanager.dart';

/// Whether the test was started with `--dart-define=MOCK_REPOSITORIES=true`, the switch
/// that selects the app's mock flavour (mock card artwork, mock DigiD, mock QR decoding).
const bool kMockFlavour = bool.fromEnvironment('MOCK_REPOSITORIES');

bool _coreInitialised = false;

/// Points the app's `wallet_core` bindings at the in-memory mock, as `main.dart` does for
/// the mock flavour. The mock is a set of top-level singletons, so its state (registered,
/// locked, cards, history) outlives a test: every test starts with [resetMockWallet].
void initMockCore() {
  if (_coreInitialised) return;
  core.WalletCore.initMock(api: mock.api);
  _coreInitialised = true;
}

/// Channels the app sent a message to during this isolate's run, for the README's list
/// of what a device would have answered.
final Set<String> touchedChannels = <String>{};

/// No deeplink ever arrives from the operating system; see `Shell.openDeeplink` for how
/// the harness opens one.
class _FakeAppLinks extends AppLinksPlatform {
  @override
  Future<Uri?> getInitialLink() async => null;

  @override
  Future<String?> getInitialLinkString() async => null;

  @override
  Future<Uri?> getLatestLink() async => null;

  @override
  Future<String?> getLatestLinkString() async => null;

  @override
  Stream<Uri> get uriLinkStream => const Stream<Uri>.empty();

  @override
  Stream<String> get stringLinkStream => const Stream<String>.empty();
}

/// No notification is ever shown or scheduled; nothing was launched from one.
class _FakeLocalNotifications extends FlutterLocalNotificationsPlatform {
  @override
  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails() async => null;

  @override
  Future<void> show({required int id, String? title, String? body, String? payload}) async {}

  @override
  Future<void> cancel({required int id}) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> cancelAllPendingNotifications() async {}

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async => const [];

  @override
  Future<List<ActiveNotification>> getActiveNotifications() async => const [];
}

/// Background sync is never scheduled.
class _FakeWorkmanager extends WorkmanagerPlatform {
  @override
  Future<void> initialize(Function callbackDispatcher, {bool isInDebugMode = false}) async {}

  @override
  Future<void> registerPeriodicTask(
    String uniqueName,
    String taskName, {
    Duration? frequency,
    Duration? flexInterval,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingPeriodicWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    ForegroundServiceConfig? foregroundServiceConfig,
  }) async {}

  @override
  Future<String> printScheduledTasks() async => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

/// Replaces what the host platform would provide. Call before the app is pumped.
///
/// [permissionsGranted] is the answer to every runtime permission the app checks or
/// requests (camera, notifications, Bluetooth): false is a phone on which the user has not
/// been asked yet, true one on which they have said yes.
void installPlatformFakes(WidgetTester tester, {bool permissionsGranted = false}) {
  AppLinksPlatform.instance = _FakeAppLinks();
  FlutterLocalNotificationsPlatform.instance = _FakeLocalNotifications();
  // The plugin's facade installs the host's implementation the first time it is
  // constructed (macOS here), so construct it before replacing that.
  Workmanager();
  WorkmanagerPlatform.instance = _FakeWorkmanager();
  // A freshly installed app: no stored language, tour, revocation-code or notification
  // preference.
  SharedPreferences.setMockInitialValues(<String, Object>{});
  // What the About screen and the menu print as the app version (pubspec.yaml).
  PackageInfo.setMockInitialValues(
    appName: 'NL Wallet',
    packageName: 'nl.ictu.edi.wallet.latest',
    version: '0.7.2',
    buildNumber: '1',
    buildSignature: '',
  );

  // rootBundle caches the Future of every string and manifest it has loaded. A future
  // completed in an earlier test belongs to that test's fake-async zone, which no longer
  // runs, so awaiting it from this test would never return (the help screens stayed on
  // their loading state from the second test on).
  rootBundle.clear();

  // A release build has no "DEBUG" ribbon; under `flutter test` MaterialApp would paint
  // one over the top-right corner of every screen, where the app has buttons.
  WidgetsApp.debugAllowBannerOverride = false;
  addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);

  // The app is in the foreground. Without this the binding has no lifecycle state and
  // the app's PrivacyCover (lib/src/feature/common/widget/privacy_cover.dart) treats it
  // as backgrounded and paints its logo cover over every screen.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.allMessagesHandler = (channel, handler, message) async {
    if (!channel.startsWith('flutter/')) touchedChannels.add(channel);
    return handler?.call(message);
  };
  addTearDown(() => messenger.allMessagesHandler = null);

  void answer(String channel, Object? Function(MethodCall call) handler) {
    final methodChannel = MethodChannel(channel);
    messenger.setMockMethodCallHandler(methodChannel, (call) async => handler(call));
    addTearDown(() => messenger.setMockMethodCallHandler(methodChannel, null));
  }

  // A phone with an enrolled fingerprint (class 3 / "strong" on Android), which is what
  // makes the app offer biometric unlock in its settings.
  answer(
    'plugins.flutter.io/local_auth',
    (call) => switch (call.method) {
      'getAvailableBiometrics' => <String>['fingerprint', 'strong'],
      'isDeviceSupported' => true,
      _ => false,
    },
  );
  // permission_handler: 0 = denied (not asked yet), 1 = granted.
  final status = permissionsGranted ? 1 : 0;
  answer(
    'flutter.baseflow.com/permissions/methods',
    (call) => switch (call.method) {
      'checkPermissionStatus' => status,
      'requestPermissions' => <int, int>{for (final permission in call.arguments as List) permission as int: status},
      'checkServiceStatus' => 1,
      'shouldShowRequestPermissionRationale' => false,
      'openAppSettings' => true,
      _ => null,
    },
  );
  // The app's own Bluetooth plugin (plugins/bluetooth): the radio is on.
  answer('bluetooth', (call) => call.method == 'isBluetoothEnabled' ? true : null);
  // The camera: authorised once the camera permission is, and "started" with a preview
  // texture that never receives a frame (the viewfinder area stays empty; nothing is ever
  // scanned).
  answer(
    'dev.steenbakker.mobile_scanner/scanner/method',
    (call) => switch (call.method) {
      'state' => permissionsGranted ? 1 : 0,
      'request' => permissionsGranted,
      'start' => <String, Object?>{
        'textureId': 1,
        'size': <String, Object?>{'width': 1080.0, 'height': 1920.0},
        'numberOfCameras': 2,
        'currentTorchState': 0,
        'cameraDirection': 1,
        'handlesCropAndRotation': true,
        'naturalDeviceOrientation': 'PORTRAIT_UP',
        'sensorOrientation': 90,
      },
      _ => null,
    },
  );
  answer('dev.steenbakker.mobile_scanner/scanner/event', (_) => null);
  answer('dev.steenbakker.mobile_scanner/scanner/deviceOrientation', (_) => null);
  // A phone lying still: the gyroscope (used for the holograph sheen on mock cards) is
  // there and reports nothing.
  answer('dev.fluttercommunity.plus/sensors/method', (_) => null);
  answer('dev.fluttercommunity.plus/sensors/gyroscope', (_) => null);
}

/// The widget tree of `mainImpl()` in lib/main.dart, verbatim, with two differences: the
/// root check is answered "not rooted" through `RootChecker.customRootCheck` (the plugin
/// has no host), and a `Directionality` sits above it. The latter is needed because under
/// `flutter test` the app's loading indicator is determinate (`Environment.isTest`), so it
/// has a semantics value, which Flutter asserts a text direction for; on a device the
/// indicator shown before `MaterialApp` exists is indeterminate and needs none.
class A11yWalletApp extends StatelessWidget {
  const A11yWalletApp({required this.navigatorKey, super.key});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: RootChecker(
        customRootCheck: (_) async => false,
        child: WalletDependencyProvider(
          navigatorKey: navigatorKey,
          builder: (context) => FlutterAppConfigurationProvider(
            builder: (config) => AutoLockObserver(
              configuration: config,
              autoLockService: context.read(),
              child: ConfigExpiryChecker(
                child: MaintenanceChecker(
                  child: UpdateChecker(
                    child: PrivacyCover(
                      child: WalletApp(navigatorKey: navigatorKey),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
