import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musly/l10n/app_localizations.dart';
import 'package:musly/providers/auth_provider.dart';
import 'package:musly/screens/auth/login_screen.dart';
import 'package:musly/services/local_music_service.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/services/tv_detection_service.dart';
import 'package:provider/provider.dart';

import '../bootstrap.dart';

class _RecordingAuth extends AuthProvider {
  _RecordingAuth() : super(SubsonicService(), StorageService());

  final lanUrls = <String?>[];
  final serverUrls = <String>[];

  @override
  Future<bool> login({
    required String serverUrl,
    required String username,
    required String password,
    bool useLegacyAuth = false,
    bool allowSelfSignedCertificates = false,
    String? customCertificatePath,
    String? clientCertificatePath,
    String? clientCertificatePassword,
    String? profileName,
    String? lanUrl,
    String serverFamily = 'subsonic',
  }) async {
    serverUrls.add(serverUrl);
    lanUrls.add(lanUrl);
    return false;
  }
}

void main() {
  initializeTestEnvironment();

  Future<_RecordingAuth> showLogin(WidgetTester tester) async {
    final auth = _RecordingAuth();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<TvDetectionService>.value(
            value: TvDetectionService()),
        ChangeNotifierProvider<LocalMusicService>.value(
            value: LocalMusicService()),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LoginScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    return auth;
  }

  Future<void> signIn(WidgetTester tester,
      {required String server, required String lan}) async {
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Server URL'), server);
    await tester.enterText(find.byKey(const ValueKey('login-lan-url')), lan);
    await tester.enterText(find.widgetWithText(TextFormField, 'Username'), 'u');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'p');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  // RD: an address typed without its scheme is refused ("must start with https://"), or given the wrong one:
  // http for the public address sends the password in the clear, https for a LAN server without a certificate
  // never connects.
  testWidgets('an address without a scheme gets https, a LAN one http',
      (tester) async {
    final auth = await showLogin(tester);

    await signIn(tester, server: 'music.example.com', lan: 'nas.local:4533');

    expect(auth.serverUrls, ['https://music.example.com']);
    expect(auth.lanUrls, ['http://nas.local:4533']);
  });

  // RD: the scheme is added to an address that already has one, so http://music.example.com becomes
  // https://http://music.example.com.
  testWidgets('an address with a scheme is kept as typed', (tester) async {
    final auth = await showLogin(tester);

    await signIn(tester,
        server: 'http://music.example.com', lan: 'https://nas.local');

    expect(auth.serverUrls, ['http://music.example.com']);
    expect(auth.lanUrls, ['https://nas.local']);
  });

  // RD: the login screen's LAN field is never passed to login, so a first-time setup at home still goes
  // through the public address until the server is added a second time.
  testWidgets('the first login passes the LAN address on', (tester) async {
    final auth = _RecordingAuth();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<TvDetectionService>.value(
            value: TvDetectionService()),
        ChangeNotifierProvider<LocalMusicService>.value(
            value: LocalMusicService()),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LoginScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Server URL'),
        'https://music.example.com');
    await tester.enterText(
        find.byKey(const ValueKey('login-lan-url')), ' http://nas:4533 ');
    await tester.enterText(find.widgetWithText(TextFormField, 'Username'), 'u');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'p');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(auth.lanUrls, ['http://nas:4533']);
  });
}
