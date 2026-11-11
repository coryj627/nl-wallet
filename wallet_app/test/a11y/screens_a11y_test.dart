// Accessibility audit of the app's screens (flutter_a11y_test, layer "runtime"), on this
// fork only: dogfood of https://github.com/coryj627/flutter-a11y.
//
// Run with the mock flavour selected, as `flutter run` is in the README:
//
//   flutter test test/a11y --dart-define=MOCK_REPOSITORIES=true
//
// Every journey starts the real app (the widget tree of lib/main.dart over the in-memory
// mock core of packages/wallet_mock, see support/a11y_app.dart) and walks to a screen the
// way a user does: tapping, typing the PIN, opening one of the README's mock deeplinks.
// No bloc, repository or use case is mocked.
//
// Findings are RECORDED, not asserted: the RuntimeFindingsSink configured in
// flutter_test_config.dart writes them to .a11y/flutter/runtime-findings.json, and
// `a11y_check_flutter scan` decides against the committed baseline what fails CI. What was
// and was not audited, with pump-time exceptions per screen, is written to
// .a11y/flutter/runtime-screens.json. See README.md in this directory.
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/src/feature/pin_timeout/pin_timeout_screen.dart';
import 'package:wallet/src/navigation/wallet_routes.dart';

import 'support/a11y_app.dart';
import 'support/a11y_harness.dart';

/// The PIN of the mock flavour's demo wallet (`SetupMockedWalletUseCaseImpl`).
const _pin = '000000';

/// A PIN the app accepts as a new one (not sequential, not repeating).
const _newPin = '135246';

/// Routes of `WalletRoutes` that no journey reaches, and why. The coverage test at the
/// end fails when a route is neither audited nor listed here, so a route added upstream
/// cannot go unnoticed.
const _notAudited = <String, String>{
  WalletRoutes.splashRoute:
      'transient: under `flutter test` the splash screen navigates away in its first frames '
      '(SplashBloc skips its delay when Environment.isTest), so there is no settled frame to audit',
  WalletRoutes.organizationDetailRoute:
      'nothing in lib/ navigates to this route by name; the screen it builds (OrganizationDetailScreen) is '
      'audited where the app opens it, as organization/detail and disclosure/organization',
  WalletRoutes.loginDetailRoute:
      'nothing in lib/ navigates to this route by name; the screen it builds (LoginDetailScreen) is '
      'audited where the app opens it, as disclosure/login-detail',
  WalletRoutes.walletTransferSourceRoute:
      'needs a second device: the route is opened by scanning the QR code another phone shows '
      'while it waits in the transfer flow; the mock core has one wallet',
};

void main() {
  setUpAll(() {
    if (!kMockFlavour) {
      fail(
        'Run with --dart-define=MOCK_REPOSITORIES=true: the audit pumps the mock flavour '
        '(mock card artwork, mock DigiD, mock deeplinks), see test/a11y/README.md.',
      );
    }
  });
  tearDownAll(ScreenLog.flush);

  group('first run', () {
    testWidgets('demo notice, introduction, PIN setup', (tester) async {
      await journey(tester, wallet: Wallet.fresh, [
        'audit demo',
        'tap Start demo app',
        'audit introduction/page-1',
        'tap Next',
        'audit introduction/page-2',
        'tap Next',
        'audit introduction/page-3',
        'tap Next',
        'audit introduction/privacy',
        'tap Read the privacy statement',
        'audit privacy-policy',
        'back',
        'tap Next',
        'audit setup-security/choose-pin',
        'pin $_newPin',
        'audit setup-security/repeat-pin',
        'pin $_newPin',
        'audit setup-security/secured',
        'tap Next',
        'audit revocation-code/write-down',
      ]);
    });

    testWidgets('PIN setup, rejected PIN', (tester) async {
      await journey(tester, wallet: Wallet.fresh, [
        'tap Start demo app',
        'tap Skip',
        'tap Next',
        'pin 123456',
        'audit setup-security/pin-too-simple',
      ]);
    });

    testWidgets('personal data from DigiD', (tester) async {
      await journey(tester, wallet: Wallet.fresh, [
        'tap Start demo app',
        'tap Skip',
        'tap Next',
        'pin $_newPin',
        'pin $_newPin',
        'tap Next',
        'tap I have written it down',
        'audit personalize/digid-intro',
        // The mock flavour's stand-in for the DigiD app (not a screen of the product, so
        // not audited): a splash, then any PIN.
        'tap Open the DigiD app',
        'wait 4',
        'pin 112233',
        'tap login',
        'wait 4',
        'audit personalize/check-data',
        'tap Add',
        'audit personalize/confirm-pin',
        'pin $_newPin',
        'wait 3',
        'audit personalize/success',
      ]);
    });

    testWidgets('move wallet from another device', (tester) async {
      await journey(tester, wallet: Wallet.fresh, [
        'tap Start demo app',
        'tap Skip',
        'tap Next',
        'pin $_newPin',
        'pin $_newPin',
        'push ${WalletRoutes.walletTransferTargetRoute}',
        'audit wallet-transfer/target-intro',
      ]);
    });
  });

  group('overview', () {
    testWidgets('dashboard and its sheets', (tester) async {
      await journey(tester, [
        'audit dashboard',
        'tap Start your action',
        'audit dashboard/qr-action-sheet',
      ]);
    });

    testWidgets('notification permission sheet', (tester) async {
      // Shown two seconds into the second visit to the dashboard.
      await journey(tester, [
        'push ${WalletRoutes.menuRoute}',
        'back',
        'wait 3',
        'audit dashboard/notification-permission-sheet',
      ]);
    });

    testWidgets('inactivity warning', (tester) async {
      await journey(tester, [
        'wait 61',
        'audit dialog/idle-warning',
      ]);
    });

    testWidgets('locked', (tester) async {
      await journey(tester, [
        'lock',
        'audit pin/unlock',
        'pin 111111',
        'audit pin/wrong-pin-dialog',
      ]);
    });

    testWidgets('menu', (tester) async {
      await journey(tester, [
        'push ${WalletRoutes.menuRoute}',
        'audit menu',
        'tap About this app',
        'audit about',
        'back',
        'tap Activities',
        'audit history',
        'tap Personal data',
        'audit history/detail-issuance',
      ]);
    });

    // The menu row that opens this developer showcase exists in non-release builds only
    // (MenuScreen.showDesignSystemRow = !kReleaseMode); its ids start with debug/.
    testWidgets('design system', (tester) async {
      await journey(tester, [
        'push ${WalletRoutes.menuRoute}',
        'tap Design System',
        'audit debug/design-system-buttons',
        'tap TextStyles',
        'audit debug/design-system-text-styles',
        'tap Colors',
        'audit debug/design-system-colors',
        'tap Other',
        'audit debug/design-system-other',
      ]);
    });
  });

  group('cards', () {
    testWidgets('card detail and what it links to', (tester) async {
      await journey(tester, [
        'tap Personal data',
        'audit card/detail',
        'tap Details in this card',
        'audit card/data',
        'tap Are your details incorrect?',
        'audit card/data-incorrect',
        'back',
        'back',
        'tap Card activities',
        'audit card/history',
        'back',
        'tap About the issuer',
        'audit organization/detail',
        'tap Would you like to report a problem?',
        'audit organization/report-issue',
      ]);
    });

    testWidgets('renew personal data', (tester) async {
      await journey(tester, [
        'tap Personal data',
        'tap Replace card via DigiD',
        'audit renew-pid/digid-intro',
        'tap Open the DigiD app',
        'wait 4',
        'pin 112233',
        'tap login',
        'wait 4',
        'audit renew-pid/check-data',
      ]);
    });

    testWidgets('address card', (tester) async {
      await journey(tester, [
        'tap Residential address',
        'audit card/detail-address',
      ]);
    });
  });

  group('settings', () {
    testWidgets('settings', (tester) async {
      await journey(tester, [
        'push ${WalletRoutes.menuRoute}',
        'tap Settings and security',
        'audit settings',
        'tap Unlock with fingerprint',
        'audit settings/biometrics',
        'back',
        'tap Change language',
        'audit settings/language',
        'back',
        'tap Move NL Wallet',
        'audit settings/wallet-transfer-faq',
        'back',
        'tap Notifications',
        'audit settings/notifications',
        'back',
        'tap View your deletion code',
        'audit settings/revocation-code',
        'tap View',
        'audit settings/revocation-code-pin',
        'pin $_pin',
        'audit settings/revocation-code-shown',
      ]);
    });

    testWidgets('change PIN', (tester) async {
      await journey(tester, [
        'push ${WalletRoutes.menuRoute}',
        'tap Settings and security',
        'tap Change PIN',
        'audit change-pin/current',
        'pin $_pin',
        'audit change-pin/new',
        'pin $_newPin',
        'audit change-pin/repeat',
        'pin $_newPin',
        'wait 3',
        'audit change-pin/done',
      ]);
    });

    testWidgets('remove data', (tester) async {
      await journey(tester, [
        'push ${WalletRoutes.menuRoute}',
        'tap Settings and security',
        'tap Remove data',
        'audit settings/remove-data-dialog',
      ]);
    });
  });

  group('help', () {
    testWidgets('help, category to topic', (tester) async {
      await journey(tester, [
        'push ${WalletRoutes.menuRoute}',
        'tap Help and information',
        'audit help',
        'tap Getting started',
        'audit help/category',
        'tap Introduction',
        'audit help/subcategory',
        'tap What',
        'audit help/topic',
      ]);
    });

    testWidgets('contact', (tester) async {
      await journey(tester, [
        'push ${WalletRoutes.menuRoute}',
        'tap Help and information',
        'tap Contact',
        'audit contact',
      ]);
    });

    testWidgets('tour', (tester) async {
      await journey(tester, [
        'push ${WalletRoutes.menuRoute}',
        'tap Help and information',
        'tap See how NL Wallet works',
        'audit tour',
        'sem Play video "How do I use my cards?"',
        'audit tour/video-unavailable',
      ]);
    });
  });

  group('QR', () {
    testWidgets('scan, camera not allowed yet', (tester) async {
      await journey(tester, [
        'tap Start your action',
        'tap Scan a QR code',
        'audit! qr/scan-camera-permission',
      ]);
    });

    testWidgets('scan, camera allowed', (tester) async {
      await journey(tester, permissionsGranted: true, [
        'tap Start your action',
        'tap Scan a QR code',
        'audit! qr/scan',
      ]);
    });

    testWidgets('show QR code', (tester) async {
      await journey(tester, permissionsGranted: true, [
        'tap Start your action',
        'tap Show your QR code',
        'wait 2',
        'audit qr/present',
      ]);
    });
  });

  group('sharing', () {
    testWidgets('share data (parking permit)', (tester) async {
      await journey(tester, [
        'link {"id":"PARKING_PERMIT","type":"verify"}',
        'audit disclosure/check-origin',
        'tap Yes, continue',
        'audit disclosure/confirm',
        'sem About Gemeente Den Haag',
        'audit disclosure/organization',
        'back',
        'tap Share',
        'audit disclosure/confirm-pin',
        'pin $_pin',
        'audit disclosure/success',
        'tap See activity',
        'audit history/detail-disclosure',
      ]);
    });

    testWidgets('share data, stop', (tester) async {
      await journey(tester, [
        'link {"id":"PARKING_PERMIT","type":"verify"}',
        'tap Stop',
        'audit disclosure/stop-sheet',
        'tap Yes, stop',
        'audit disclosure/stopped',
      ]);
    });

    testWidgets('share data, card missing', (tester) async {
      await journey(tester, [
        'link {"id":"JOB_APPLICATION","type":"verify"}',
        'audit disclosure/missing-attributes',
        'tap See details',
        'audit disclosure/missing-attributes-details',
      ]);
    });

    testWidgets('log in (Gemeente Amsterdam)', (tester) async {
      await journey(tester, [
        'link {"id":"AMSTERDAM_LOGIN","type":"verify"}',
        'tap Yes, continue',
        'audit disclosure/login-confirm',
        'tap Check all details',
        'audit disclosure/login-detail',
      ]);
    });

    testWidgets('history after sharing', (tester) async {
      await journey(tester, [
        'link {"id":"PARKING_PERMIT","type":"verify"}',
        'tap Yes, continue',
        'tap Share',
        'pin $_pin',
        'tap To my overview',
        // The second visit to the dashboard: the notification question comes up after two
        // seconds (audited on its own above); answer it as a user would.
        'wait 3',
        'tap Not now',
        'audit dashboard/after-sharing',
        'tap Personal data',
        'tap Card activities',
        'audit card/history-shared',
      ]);
    });
  });

  group('receiving cards', () {
    testWidgets('driving licence', (tester) async {
      await journey(tester, [
        'link {"id":"DRIVING_LICENSE","type":"issue"}',
        'audit issuance/share-to-receive',
        'tap See what data you are sharing',
        'audit issuance/request-details',
        'back',
        'tap Share',
        'audit issuance/share-pin',
        'pin $_pin',
        'audit issuance/review-card',
        'tap Check details',
        'audit issuance/card-details',
        'back',
        'tap Add 1 card',
        'pin $_pin',
        'audit issuance/success',
        'tap To my overview',
        'wait 3',
        'tap Not now',
        'audit dashboard/three-cards',
        'tap Driving License',
        'audit card/detail-driving-licence',
        'tap Delete card',
        'audit card/delete-dialog',
        'tap Yes, delete',
        'audit card/delete-confirm-pin',
        'pin $_pin',
        'wait 2',
        'audit card/delete-done',
      ]);
    });

    testWidgets('several diplomas', (tester) async {
      await journey(tester, [
        'link {"id":"MULTI_DIPLOMA","type":"issue"}',
        'tap Share',
        'pin $_pin',
        'audit issuance/review-several-cards',
      ]);
    });

    testWidgets('receiving cards, stop', (tester) async {
      await journey(tester, [
        'link {"id":"DRIVING_LICENSE","type":"issue"}',
        'tap Stop',
        'audit issuance/stop-sheet',
        'tap Yes, stop',
        'audit issuance/stopped',
      ]);
    });
  });

  group('signing', () {
    testWidgets('rental agreement', (tester) async {
      await journey(tester, [
        'link {"id":"RENTAL_AGREEMENT","type":"sign"}',
        'audit sign/check-organization',
        'tap Share',
        'audit sign/check-agreement',
        'tap Yes, next',
        'audit sign/confirm',
        'tap Yes, sign',
        'audit sign/confirm-pin',
        'pin $_pin',
        'audit sign/success',
      ]);
    });
  });

  group('PIN trouble and blocked states', () {
    testWidgets('forgot PIN, recovery', (tester) async {
      await journey(tester, [
        'lock',
        'tap Forgot PIN?',
        'audit forgot-pin',
        'tap Create a new PIN',
        'audit pin-recovery/digid-intro',
        'tap Open the DigiD app',
        'wait 4',
        'pin 112233',
        'tap login',
        'wait 4',
        'audit pin-recovery/choose-pin',
      ]);
    });

    testWidgets('PIN timeout', (tester) async {
      await journey(tester, [
        (Shell shell) async => PinTimeoutScreen.show(shell.context, DateTime.now().add(const Duration(minutes: 15))),
        'audit pin-timeout',
      ]);
    });

    for (final (id, route) in const [
      ('pin-blocked', WalletRoutes.pinBlockedRoute),
      ('app-blocked', WalletRoutes.appBlockedRoute),
      ('invariant-error', WalletRoutes.invariantErrorRoute),
      ('recover-session', WalletRoutes.recoverSessionRoute),
      ('update-info', WalletRoutes.updateInfoRoute),
      // Nothing in lib/ navigates to this route by name (a locked wallet shows the same
      // PinScreen through PinOverlay, audited as pin/unlock); it is in the route table.
      ('pin/route', WalletRoutes.pinRoute),
    ]) {
      testWidgets(id, (tester) async {
        await journey(tester, ['push $route', 'audit $id']);
      });
    }
  });

  test('route coverage', () {
    final audited = <String, List<String>>{};
    for (final entry in ScreenLog.entries) {
      if (entry.value['status'] != 'audited') continue;
      final route = (entry.value['route'] ?? entry.value['over']) as String?;
      if (route != null) audited.putIfAbsent(route, () => []).add(entry.key);
    }
    final table = WalletRoutes.allRoutes;
    final missing = [
      for (final route in table)
        if (!audited.containsKey(route) && !_notAudited.containsKey(route)) route,
    ];
    ScreenLog.summary.addAll({
      'routeTable': table.length,
      'routesAudited': {
        for (final route in table)
          if (audited.containsKey(route)) route: audited[route],
      },
      'routesNotAudited': {
        for (final route in table)
          if (!audited.containsKey(route)) route: _notAudited[route] ?? 'no journey reached it in this run',
      },
      if (pendingFailures.isNotEmpty) 'journeyFailures': pendingFailures,
    });
    // ignore: avoid_print
    print(
      'a11y routes: ${table.where(audited.containsKey).length} of ${table.length} in the route table audited; '
      'not audited: ${table.where((r) => !audited.containsKey(r)).join(', ')}',
    );
    expect(missing, isEmpty, reason: 'routes neither audited nor listed in _notAudited');
  });
}
