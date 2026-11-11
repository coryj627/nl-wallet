# Runtime accessibility audit (dogfood of flutter-a11y)

This directory exists on the `coryj627/nl-wallet` fork only. It pumps the app's screens under
`flutter test` and records what [`flutter_a11y_test`](https://github.com/coryj627/flutter-a11y)
0.4.1 finds on the rendered semantics tree. The findings are hand-labelled later to measure the
precision of each rule on a real application, so the aim is screens pumped as a user sees them,
not a small number of findings. Nothing under `lib/` and none of the app's own tests is changed.

## Run

```sh
cd wallet_app
flutter test test/a11y --dart-define=MOCK_REPOSITORIES=true
```

About 75 s on an M-series Mac (40 tests, 105 audits). Without the define the run stops at once
with a message: the audit pumps the mock flavour, and `MOCK_REPOSITORIES` is a compile-time
constant.

Outputs, both under `wallet_app/.a11y/flutter/` and both git-ignored:

- `runtime-findings.json`: the findings, in the format `a11y_check_flutter scan` merges
  (`scan.runtime_report` in `.a11y/a11y-check-flutter.yaml`).
- `runtime-screens.json`: one entry per screen id (audited or not, the route it was on, the
  viewport it was grown to, pump-time exceptions and uncaught async errors), the channels the
  app sent messages to, and the route-table coverage.

`A11Y_SCREENSHOTS=<directory>` in the environment also writes a PNG of each screen as it is
audited, for the people labelling the findings.

Two consecutive runs produce byte-identical files (checked three times on 2026-11-10: 95
findings each).

## What is pumped

The real app in its **mock flavour**, as the README describes it ("Running the app", "Mock"):
`support/a11y_app.dart` builds the widget tree of `mainImpl()` in `lib/main.dart`
(`RootChecker` → `WalletDependencyProvider` → `FlutterAppConfigurationProvider` →
`AutoLockObserver` → `ConfigExpiryChecker` → `MaintenanceChecker` → `UpdateChecker` →
`PrivacyCover` → `WalletApp`) over `packages/wallet_mock`, the in-memory implementation of the
Rust core that `main.dart` installs when `MOCK_REPOSITORIES=true`. Every bloc, use case,
repository, mapper and service is the app's own, created by the app's own providers; the route
table, the theme and the localisation delegates are the app's.

**No bloc, repository or use case is mocked**, and the app's test wrapper
(`test/wallet_app_test_widget.dart`) is not used: it puts every screen inside an extra
`Scaffold` and feeds screens hand-built bloc states, which is right for goldens and less
faithful than the running app for this purpose. From the app's test support only
`test/flutter_test_config.dart` is reused (see "Sink wiring").

Each test is a **journey**: it starts the app cold and walks to a screen the way a user does,
in a small step language (`support/a11y_harness.dart`, `Step`): tap a text, type on the PIN
keyboard, press back, wait, lock the wallet, open one of the README's mock deeplink scenarios,
audit. A journey that cannot take a step stops; every `audit` after that step is recorded in
`runtime-screens.json` as `failed` with the step and what was on screen, and the run goes on.

Two starting states:

- `Wallet.fresh`: a new install (no PIN, no cards). The app opens on its demo notice.
- `Wallet.ready`: the app's own `SetupMockedWalletUseCase` followed by a replace-push of the
  dashboard, which is exactly what the introduction screen's "Skip Setup" button does in debug
  mock builds. PIN `000000`, unlocked, with the mock "Personal data" and "Residential address"
  cards (Willeke Liselotte de Bruijn, Den Haag) and their two history entries.

Deeplinks (`link …` steps) are decoded by the app's `DecodeUriUseCase` and handed to its
`NavigationService`, which is what `DeeplinkService` does with a link from the operating
system. The service itself cannot be fed from a test; see "Friction".

## Screens audited: 105 screen ids, 47 of the 51 routes in `WalletRoutes`

"Route" is the route on top of the navigator when the screen was audited; `over …` means a
dialog, a bottom sheet or a screen the app pushes without a route name, on top of that route.
Viewport is logical px (see "Harness decisions"). Findings are the count on 2026-11-10.

| Screen id | Route | Viewport | Findings |
|---|---|---|---|
| `about` | `/about` | 412x915 | 0 |
| `app-blocked` | `/blocked` | 412x915 | 2 |
| `card/data` | `/card/data` | 412x1008 | 0 |
| `card/data-incorrect` | `over /card/data` | 412x915 | 0 |
| `card/delete-confirm-pin` | `/card/delete` | 412x915 | 1 |
| `card/delete-dialog` | `over /card/detail` | 412x915 | 1 |
| `card/delete-done` | `/card/delete` | 412x915 | 1 |
| `card/detail` | `/card/detail` | 412x915 | 0 |
| `card/detail-address` | `/card/detail` | 412x915 | 0 |
| `card/detail-driving-licence` | `/card/detail` | 412x915 | 0 |
| `card/history` | `/card/history` | 412x915 | 0 |
| `card/history-shared` | `/card/history` | 412x915 | 0 |
| `change-pin/current` | `/change_pin` | 412x915 | 1 |
| `change-pin/done` | `/change_pin` | 412x915 | 1 |
| `change-pin/new` | `/change_pin` | 412x915 | 1 |
| `change-pin/repeat` | `/change_pin` | 412x915 | 1 |
| `contact` | `/menu/contact` | 412x915 | 0 |
| `dashboard` | `/dashboard` | 412x1051 | 2 |
| `dashboard/after-sharing` | `/dashboard` | 412x1073 | 2 |
| `dashboard/notification-permission-sheet` | `over /dashboard` | 412x1051 | 1 |
| `dashboard/qr-action-sheet` | `over /dashboard` | 412x915 | 1 |
| `dashboard/three-cards` | `/dashboard` | 412x1573 | 2 |
| `debug/design-system-buttons` | `/theme` | 412x1531 | 2 |
| `debug/design-system-colors` | `/theme` | 412x1710 | 0 |
| `debug/design-system-other` | `/theme` | 412x8000 | 8 |
| `debug/design-system-text-styles` | `/theme` | 412x1510 | 1 |
| `demo` | `/demo` | 412x915 | 0 |
| `dialog/idle-warning` | `over /dashboard` | 412x1051 | 1 |
| `disclosure/check-origin` | `/disclosure` | 412x915 | 1 |
| `disclosure/confirm` | `/disclosure` | 412x1088 | 0 |
| `disclosure/confirm-pin` | `/disclosure` | 412x915 | 1 |
| `disclosure/login-confirm` | `/disclosure` | 412x915 | 0 |
| `disclosure/login-detail` | `over /disclosure` | 412x915 | 0 |
| `disclosure/missing-attributes` | `/disclosure` | 412x915 | 2 |
| `disclosure/missing-attributes-details` | `over /disclosure` | 412x915 | 0 |
| `disclosure/organization` | `over /disclosure` | 412x915 | 0 |
| `disclosure/stop-sheet` | `over /disclosure` | 412x915 | 0 |
| `disclosure/stopped` | `/disclosure` | 412x915 | 1 |
| `disclosure/success` | `/disclosure` | 412x915 | 1 |
| `forgot-pin` | `/forgot_pin` | 412x915 | 1 |
| `help` | `/menu/help` | 412x1034 | 0 |
| `help/category` | `/menu/help/category` | 412x915 | 0 |
| `help/subcategory` | `/menu/help/subcategory` | 412x1086 | 0 |
| `help/topic` | `/menu/help/topic` | 412x1032 | 4 |
| `history` | `/wallet/history` | 412x915 | 0 |
| `history/detail-disclosure` | `/history` | 412x1102 | 0 |
| `history/detail-issuance` | `/history` | 412x915 | 0 |
| `introduction/page-1` | `/introduction` | 412x915 | 0 |
| `introduction/page-2` | `/introduction` | 412x915 | 0 |
| `introduction/page-3` | `/introduction` | 412x915 | 0 |
| `introduction/privacy` | `/introduction/privacy` | 412x915 | 1 |
| `invariant-error` | `/invariant_error` | 412x915 | 2 |
| `issuance/card-details` | `over /issuance` | 412x1049 | 0 |
| `issuance/request-details` | `over /issuance` | 412x915 | 0 |
| `issuance/review-card` | `/issuance` | 412x915 | 0 |
| `issuance/review-several-cards` | `/issuance` | 412x915 | 0 |
| `issuance/share-pin` | `/issuance` | 412x915 | 1 |
| `issuance/share-to-receive` | `/issuance` | 412x915 | 0 |
| `issuance/stop-sheet` | `over /issuance` | 412x915 | 0 |
| `issuance/stopped` | `/issuance` | 412x915 | 1 |
| `issuance/success` | `/issuance` | 412x915 | 1 |
| `menu` | `/menu` | 412x915 | 0 |
| `organization/detail` | `over /card/detail` | 412x915 | 0 |
| `organization/report-issue` | `over /card/detail` | 412x915 | 1 |
| `personalize/check-data` | `/wallet/personalize` | 412x1336 | 0 |
| `personalize/confirm-pin` | `/wallet/personalize` | 412x915 | 1 |
| `personalize/digid-intro` | `/wallet/personalize` | 412x915 | 1 |
| `personalize/success` | `/wallet/personalize` | 412x915 | 0 |
| `pin-blocked` | `/pin/blocked` | 412x915 | 1 |
| `pin-recovery/choose-pin` | `/pin/recovery` | 412x915 | 1 |
| `pin-recovery/digid-intro` | `/pin/recovery` | 412x915 | 1 |
| `pin-timeout` | `/pin/timeout` | 412x915 | 1 |
| `pin/route` | `/pin` | 412x915 | 2 |
| `pin/unlock` | `/dashboard` | 412x1051 | 3 |
| `pin/wrong-pin-dialog` | `over /dashboard` | 412x1051 | 1 |
| `privacy-policy` | `/privacy_policy` | 412x6447 | 0 |
| `qr/present` | `/qr/present` | 412x915 | 1 |
| `qr/scan` | `/qr/scan` | 412x915 | 0 |
| `qr/scan-camera-permission` | `/qr/scan` | 412x915 | 1 |
| `recover-session` | `/recover_session` | 412x915 | 0 |
| `renew-pid/check-data` | `/pid/renew` | 412x1342 | 0 |
| `renew-pid/digid-intro` | `/pid/renew` | 412x915 | 1 |
| `revocation-code/write-down` | `/revocation_code` | 412x915 | 0 |
| `settings` | `/menu/settings` | 412x915 | 0 |
| `settings/biometrics` | `/settings/biometrics` | 412x915 | 2 |
| `settings/language` | `/language` | 412x915 | 0 |
| `settings/notifications` | `/settings/manage_notifications` | 412x915 | 1 |
| `settings/remove-data-dialog` | `over /menu/settings` | 412x915 | 1 |
| `settings/revocation-code` | `/review_revocation_code` | 412x915 | 1 |
| `settings/revocation-code-pin` | `/review_revocation_code` | 412x915 | 1 |
| `settings/revocation-code-shown` | `/review_revocation_code` | 412x915 | 0 |
| `settings/wallet-transfer-faq` | `/settings/wallet_transfer_faq` | 412x915 | 1 |
| `setup-security/choose-pin` | `/security/setup` | 412x915 | 1 |
| `setup-security/pin-too-simple` | `over /security/setup` | 412x915 | 0 |
| `setup-security/repeat-pin` | `/security/setup` | 412x915 | 1 |
| `setup-security/secured` | `/security/setup` | 412x915 | 1 |
| `sign/check-agreement` | `/sign` | 412x915 | 1 |
| `sign/check-organization` | `/sign` | 412x915 | 1 |
| `sign/confirm` | `/sign` | 412x915 | 1 |
| `sign/confirm-pin` | `/sign` | 412x915 | 1 |
| `sign/success` | `/sign` | 412x915 | 1 |
| `tour` | `/tour` | 412x2803 | 14 |
| `tour/video-unavailable` | `/tour/video` | 412x915 | 2 |
| `update-info` | `/update_info` | 412x915 | 1 |
| `wallet-transfer/target-intro` | `/wallet_transfer/target` | 412x915 | 1 |

The four `debug/design-system-*` ids are the developer showcase at `/theme`. It is in the
route table and the mock flavour reaches it, but its menu row exists in non-release builds
only (`MenuScreen.showDesignSystemRow = !kReleaseMode`). It is audited (11 of the 95 findings)
and its ids are prefixed so it can be labelled or set aside as a group. For the same reason the
`menu` screen shows a "Design System" row that a release build does not have.

## Not audited

Routes of the route table (4 of 51; `_notAudited` in the test, enforced by its `route coverage`
test, which fails when a route is neither audited nor listed with a reason):

| Route | Why |
|---|---|
| `/` (splash) | Transient. Under `flutter test` `SplashBloc` skips its delay (`Environment.isTest`) and navigates away in its first frames; there is no settled frame to audit. |
| `/organization` | Nothing in `lib/` navigates to it by name. The screen it builds, `OrganizationDetailScreen`, is audited where the app opens it (`organization/detail`, `disclosure/organization`). |
| `/login_detail` | Nothing in `lib/` navigates to it by name. `LoginDetailScreen` is audited where the app opens it (`disclosure/login-detail`). |
| `/wallet_transfer/source` | Needs a second device: it is opened by scanning the QR code another phone shows during a transfer. The mock core has one wallet. |

`/settings/developer` is not in the route table of this build: it is added only with
`--dart-define=ENABLE_WRPRC_STRICT_MODE_TOGGLE=true`.

Screens and states outside the route table that no journey reaches (not a complete list of
everything the app can show; these are the ones known to be missing):

- **Error states that need a failing core**: the generic, network and session-expired error
  pages of the disclosure, issuance, sign, personalize, renew and recovery flows. The mock
  core does not fail on request, and making it fail would mean mocking a use case, which this
  harness does not do. The app's own error pages that the mock *does* produce are audited
  (`disclosure/missing-attributes`, `invariant-error`, `app-blocked`, `pin-blocked`,
  `pin-timeout`, `tour/video-unavailable`).
- **App-level blockers**: root detected, configuration expired, maintenance window, update
  required. The mock core reports version OK, configuration valid, no maintenance; the root
  check is answered "not rooted".
- **Card states other than valid**: expired, revoked, corrupted, expiring soon, and the
  dashboard banners that go with them. The mock issues valid cards only.
- **Empty history**: a wallet that reaches the history screen always has its issuance events.
- **Later steps of flows**: PIN recovery after choosing the new PIN, renewal after checking the
  data, moving a wallet after the first question, contactless (Bluetooth) disclosure after the
  QR code is shown, the card preview and "check attributes" screens inside disclosure.
- **The mock DigiD screens** (a splash, a PIN pad, a login confirmation). They are the mock
  flavour's stand-in for the external DigiD app, not screens of the product; journeys pass
  through them without auditing.
- **The tour video player.** `flutter test` has no video platform, so the app shows its own
  "something went wrong" page, which is what is audited as `tour/video-unavailable`.
- **Dutch, dark mode, landscape, large text as a starting state.** Everything is audited in
  English, light, portrait, at text scale 1 (the audit itself re-lays each screen out at 200 %
  text and at 320 px width). English because the app's `LocalizedText.l10nValue` returns the
  English value whenever `Environment.isTest`, so a Dutch run would show Dutch chrome around
  English data.

## Harness decisions that affect findings

- **Mock flavour, debug mode.** `MOCK_REPOSITORIES=true` selects mock card artwork
  (`MockCardBackground`, `MockCardHolograph`), which contrast findings on cards are measured
  against. `flutter test` is a debug build: the "Design System" menu row is there.
- **`Environment.isTest` is true and cannot be turned off** (the app reads the `FLUTTER_TEST`
  environment variable). In `lib/` it changes: Lottie animations do not play; the loading
  indicator is a half-filled determinate ring instead of a spinner; data labels and values come
  in English regardless of locale; the introduction's "Skip Setup" debug button is hidden; the
  OS version on the About screen reads "1.0"; several delays are zero.
- **Viewport.** 412×915 logical px at device pixel ratio 3, the same as flutter-a11y's
  `tool/score_realapps_runtime`. (The app's own goldens use 375×812 at 1.)
- **Growing the view.** Before a screen is audited the view is made taller until none of its
  vertical scrollables has anything left to scroll (cap 8000 px), so content below the fold is
  built, has semantics and is audited as if scrolled through. The view goes back to 412×915
  before the next step. Consequences: sticky bottom bars sit at the bottom of the grown view;
  a dialog or the PIN overlay on top of the dashboard is audited at the dashboard's grown
  height (`pin/unlock`, `pin/wrong-pin-dialog`, `dialog/idle-warning` and
  `dashboard/notification-permission-sheet` at 412×1051). `qr/scan*` are not grown (`audit!`):
  their layout is the viewport. Only `debug/design-system-other` reaches the cap. No screen
  reports a remaining scroll extent.
- **Fonts.** The app's own fonts (RijksoverheidSansWebText, WalletIcons, MaterialIcons), loaded
  by the app's own `FontUtils.loadAppFonts()` through its `test/flutter_test_config.dart`. The
  theme sets the family everywhere, so Roboto is not needed and not loaded. Screenshots confirm
  real glyphs on every screen. Even so the audit reports its `default-test-font` diagnostic on 7
  screens (`introduction/page-1..3`, `introduction/privacy`, `setup-security/choose-pin`,
  `setup-security/repeat-pin`, `personalize/confirm-pin`); see "Friction" for why that is a
  false alarm. Its effect is that an overflow finding text takes part in would be tiered
  "needs review" on those screens. There are no overflow findings in this run.
- **Audit configuration.** `A11yAuditConfig(platform: null, reflow: true, sourceRoots:
  [<wallet_app>/lib/])`: all 19 rules, both platform tap-target guidelines (a small control can
  be reported twice), the 200 % text and 320 px passes, attribution to `lib/` only. Nothing is
  disabled and no screen is skipped.
- **Record, do not assert.** `auditScreen`, never `expectAccessible`. A test fails only when
  the harness itself breaks, when the define is missing, or when a route is neither audited nor
  listed (`route coverage`).
- **Time.** Tests run on flutter_test's fake clock, which starts at the real time, so history
  entries carry today's date. No finding message contains a date today; a finding whose label
  included one would change its text from day to day.
- **Things switched off because a device does not have them.** The "DEBUG" ribbon
  (`WidgetsApp.debugAllowBannerOverride = false`): it would be painted over the top-right
  corner, where most screens have a button. The app lifecycle is set to `resumed`: with no
  lifecycle state the app's `PrivacyCover` paints its logo cover over every screen (the first
  runs of this harness had one `image-missing-label` on every screen for that reason).
- **One harness widget above the app**: a `Directionality`. The app shows its loading indicator
  before `MaterialApp` exists; under `flutter test` that indicator is determinate, has a
  semantics value, and Flutter asserts a text direction for it. No finding can be attributed to
  it (`sourceRoots`).
- **The notification question.** The app asks about notifications two seconds into the second
  visit to the dashboard. It is audited on its own (`dashboard/notification-permission-sheet`);
  the two journeys that return to the dashboard wait for it and answer "Not now" before
  auditing the dashboard.

## What had to be faked

Only what a device answers. All of it is in `installPlatformFakes` (`support/a11y_app.dart`);
`channelsTouched` in `runtime-screens.json` lists the channels the app actually used.

| What | Answer |
|---|---|
| `wallet_core` (Rust) | `packages/wallet_mock`, installed with `WalletCore.initMock` as `main.dart` does. Its state is a set of isolate-wide singletons, so every journey first cancels any open session and resets the wallet. |
| Root check (`root_jailbreak_sniffer`) | "Not rooted", through `RootChecker.customRootCheck`. |
| `app_links` | A platform instance with no initial link and no incoming links. |
| `flutter_local_notifications` | A platform instance that shows and schedules nothing. |
| `workmanager` | A platform instance that schedules nothing. |
| `shared_preferences` | Empty (`setMockInitialValues`): a fresh install. |
| `package_info_plus` | NL Wallet 0.7.2 (1), which the About screen prints. |
| `local_auth` | A phone with an enrolled fingerprint (`fingerprint`, `strong`), which makes Settings offer "Unlock with fingerprint". Authentication itself answers false. |
| `permission_handler` | Every permission "denied, not asked yet", or "granted" for the two journeys started with `permissionsGranted: true` (`qr/scan`, `qr/present`). |
| `mobile_scanner` | Camera authorised when the permission is; `start` returns a preview texture that never receives a frame, so the viewfinder area is empty. Nothing is ever scanned. |
| `bluetooth` (the app's own plugin) | The radio is on. |
| `sensors_plus` | A gyroscope that reports nothing (the holograph sheen on mock cards does not move). |
| `country_codes_plus` | Not answered; the plugin itself falls back to the platform locale. |
| `video_player` | Nothing: it has no implementation on the test host, so the tour video cannot start; see `tour/video-unavailable`. |
| `url_launcher`, `screen_brightness`, `vibration` | Nothing; no journey makes the app call them. |

## Sink wiring

`test/a11y/flutter_test_config.dart` configures `RuntimeFindingsSink` and then calls the app's
own `test/flutter_test_config.dart` (fonts, mockito dummies, `OnboardingHelper`,
`VisibilityDetector` interval). Flutter uses the nearest `flutter_test_config.dart`, so the
app's other tests never see the sink and behave exactly as before.

## Friction (app and flutter_a11y_test 0.3.0)

- **`default-test-font` false alarm (flutter_a11y_test).** `onlyTestFontRendered` collects font
  families with `RenderParagraph.text.visitChildren`, and `TextSpan.visitChildren` calls the
  visitor only for spans that have text. This app builds most text as
  `Text.rich(TextSpan(children: [TextSpan(text: …, locale: …)]))`: the family is on the root
  span, which has no text, and the child that has text has no style. On a screen where every
  paragraph is built that way the detector sees only `null` and icon families and concludes
  the test font is in use.
- **Singletons that capture a test's zone.** Three things worked in the first test of the
  isolate and silently did nothing afterwards, because a future or subscription made in one
  test belongs to that test's fake-async zone, which never runs again: `rootBundle`'s string
  cache (help screens stayed on their loading state; fixed with `rootBundle.clear()` per
  journey), the `AppLinks` facade's single platform subscription (deeplinks were not delivered;
  hence `Shell.openDeeplink`), and anything cached by a plugin singleton.
- **`Workmanager()` replaces `WorkmanagerPlatform.instance`** with the host's implementation
  the first time it is constructed, so a fake has to be installed after constructing it once.
- **Reading the route stack.** There is no public way to see what is on a `Navigator` without
  an observer, and `WalletApp` creates its own observers. `Navigator.popUntil` with a predicate
  that answers false pops routes; an early version of the harness dismissed every dialog and
  sheet that way just before auditing it. The stack is now read from the `_ModalScopeStatus`
  widgets in the tree.
- **A route future that never completes.** `ForgotPinScreen.show` returns the push future;
  awaiting it in a step hangs the test.
- **Golden tests on this host.** `flutter test test/src/feature/about` fails here with a 3 %
  pixel difference; the app's goldens are host-specific (README, "UI tests"). That is unrelated
  to this harness; 139 non-golden tests of the app (route tests, menu, dashboard) pass with the
  dev dependency added.
