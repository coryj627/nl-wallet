// Picked up by `flutter test` for the files in test/a11y/ only (Flutter uses the
// nearest flutter_test_config.dart). It adds the flutter_a11y_test findings sink and
// then defers to the app's own test/flutter_test_config.dart, so the app's fonts,
// mockito dummies and other test defaults apply here exactly as in its own tests,
// and the app's own tests are untouched.
import 'dart:async';

import 'package:flutter_a11y_test/flutter_a11y_test.dart';
import 'package:flutter_test/flutter_test.dart';

import '../flutter_test_config.dart' as app;

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  RuntimeFindingsSink.configure(); // .a11y/flutter/runtime-findings.json
  tearDownAll(RuntimeFindingsSink.flush);
  await app.testExecutable(testMain);
}
