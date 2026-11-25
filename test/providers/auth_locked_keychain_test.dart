import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/server_config.dart';
import 'package:musly/providers/auth_provider.dart';
import 'package:musly/services/auth_log.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bootstrap.dart';
import '../fake_keychain.dart';
import '../fake_queue_server.dart';

/// Starting with a saved login the keychain cannot give yet.
void main() {
  initializeTestEnvironment();

  late FakeQueueServer server;
  late FakeKeychain keychain;
  late Directory logDir;
  AuthProvider? auth;

  Future<List<String>> logged() async {
    await AuthLog.instance.record('-');
    return (await File('${logDir.path}/auth_log.txt').readAsLines())
        .map((l) => l.substring(l.indexOf('] ') + 2))
        .where((l) => l != '-')
        .toList();
  }

  setUp(() async {
    server = FakeQueueServer();
    await server.start();
    final saved = ServerConfig(
        serverUrl: 'http://127.0.0.1:${server.port}',
        username: 'u',
        password: '');
    SharedPreferences.setMockInitialValues({
      'server_config': jsonEncode(saved.toJson()),
      'secrets_first_unlock': true,
    });
    final storage = StorageService();
    await storage.init();
    keychain = FakeKeychain({'server_pwd_active': 'secret'})..locked = true;
    storage
      ..secureStorage = keychain
      ..unlockedOnlyStorage = FakeKeychain()
      ..keychainHasAccessibility = true;
    AuthProvider.lockedRetry = const Duration(milliseconds: 50);
    logDir = Directory.systemTemp.createTempSync('musly_auth_log_');
    AuthLog.instance.file = () async => File('${logDir.path}/auth_log.txt');
  });

  tearDown(() async {
    auth?.dispose();
    await server.stop();
    logDir.deleteSync(recursive: true);
  });

  // RD: the locked keychain is taken for signed out, so the login screen asks for the password the phone holds;
  // or it is never read again, so the app waits on its loading screen forever once unlocked.
  test('waits for the keychain, then signs in with the saved login', () async {
    auth = AuthProvider(SubsonicService(), StorageService());
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(auth!.state, AuthState.unknown);

    keychain.locked = false;
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(auth!.state, AuthState.authenticated);
    expect(auth!.config?.password, 'secret');
    final log = await logged();
    expect(log.first, startsWith('saved login not readable yet'));
    expect(log.last, 'saved login read');
  });

  // RD: the app shows the login screen without saying why, so the next unexpected sign-out cannot be told
  // apart from a lost password or a wiped config.
  test('a saved login without its password is logged with what is missing',
      () async {
    keychain
      ..items.clear()
      ..locked = false;

    auth = AuthProvider(SubsonicService(), StorageService());
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(auth!.state, AuthState.unauthenticated);
    expect(await logged(),
        ['login screen: saved login incomplete, missing password']);
  });
}
