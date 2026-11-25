import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/server_config.dart';
import 'package:musly/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bootstrap.dart';
import '../fake_keychain.dart';

/// How the saved login's secrets are kept in the iOS keychain: readable from the phone's first unlock, and
/// never mistaken for absent when the keychain is locked.
void main() {
  initializeTestEnvironment();

  final saved = ServerConfig(
      serverUrl: 'https://music.example.com', username: 'u', password: '');
  late FakeKeychain keychain;
  late FakeKeychain unlockedOnly;
  final storage = StorageService();

  Future<void> start({
    bool withConfig = true,
    Map<String, String> old = const {},
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      if (withConfig) 'server_config': jsonEncode(saved.toJson()),
      ...prefs,
    });
    await storage.init();
    keychain = FakeKeychain();
    unlockedOnly = FakeKeychain(old);
    storage
      ..secureStorage = keychain
      ..unlockedOnlyStorage = unlockedOnly
      ..keychainHasAccessibility = true;
  }

  // RD: a keychain read that fails (the phone is locked: iOS launched the app for a lock-screen play button)
  // returns null like a missing password, so the saved login looks incomplete and the app signs out.
  test('a locked keychain is reported, not taken for a missing password',
      () async {
    await start(prefs: {'secrets_first_unlock': true});
    keychain
      ..items['server_pwd_active'] = 'secret'
      ..locked = true;

    await expectLater(storage.getServerConfig(),
        throwsA(isA<SecretsUnavailableException>()));

    keychain.locked = false;
    expect((await storage.getServerConfig())?.password, 'secret');
  });

  // RD: the secrets kept before the accessibility change are never moved, or are read only where they now
  // belong, so after the update every saved password is gone and the user is signed out.
  test('secrets kept the old way are moved to the new accessibility',
      () async {
    await start(old: {'server_pwd_active': 'secret', 'other': 'x'});

    expect((await storage.getServerConfig())?.password, 'secret');

    expect(keychain.items, {'server_pwd_active': 'secret', 'other': 'x'});
    expect(unlockedOnly.items, isEmpty);
  });

  // RD: only a signed-in launch moves the secrets, and reads look only in the new place, so the login screen's
  // saved profiles have lost their passwords when the app starts signed out.
  test('secrets not moved yet are read where they were kept', () async {
    await start(withConfig: false, old: {});
    await storage.saveProfile(ServerConfig(
        serverUrl: 'https://music.example.com',
        username: 'u',
        password: 'secret',
        name: 'home'));
    unlockedOnly.items.addAll(keychain.items);
    keychain.items.clear();

    final profiles = await storage.getSavedProfiles();

    expect(profiles.single.password, 'secret');
  });

  // RD: the move runs again on every launch, or runs while the keychain is locked and records itself done, so
  // the old secrets are never moved and stay unreadable while the phone is locked.
  test('a move the locked keychain stopped is retried at the next launch',
      () async {
    await start(old: {'server_pwd_active': 'secret'});
    unlockedOnly.locked = true;
    keychain.locked = true;
    await expectLater(storage.getServerConfig(),
        throwsA(isA<SecretsUnavailableException>()));

    unlockedOnly.locked = false;
    keychain.locked = false;
    expect((await storage.getServerConfig())?.password, 'secret');
    expect(unlockedOnly.items, isEmpty);
  });
}
