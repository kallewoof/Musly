import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Call this at the top of `main()` in any test that instantiates
/// StorageService, PlayerProvider, AuthProvider, or any class that
/// accesses SharedPreferences / native MethodChannels.
void initializeTestEnvironment() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  // A fresh directory per test file: test files run in parallel, and a shared one (the working directory)
  // let one file's cleanup delete offline_music while another file was listing it.
  final dir = Directory.systemTemp.createTempSync('musly_test_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async {
      return dir.path;
    },
  );
}
