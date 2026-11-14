import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musly/l10n/app_localizations.dart';
import 'package:musly/models/server_config.dart';
import 'package:musly/providers/auth_provider.dart';
import 'package:musly/providers/library_provider.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/screens/settings/settings_server_tab.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/jukebox_service.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/services/transcoding_service.dart';
import 'package:musly/services/upnp_service.dart';
import 'package:provider/provider.dart';

import '../bootstrap.dart';
import '../test_helpers.dart';

class _RecordingAuth extends AuthProvider {
  _RecordingAuth(SubsonicService s) : super(s, StorageService());

  final saved = <String>[];

  @override
  ServerConfig? get config => ServerConfig(
      serverUrl: 'https://music.example.com',
      lanUrl: 'http://old:4533',
      username: 'u',
      password: 'p');

  @override
  Future<void> setLanUrl(String lanUrl) async => saved.add(lanUrl);
}

void main() {
  initializeTestEnvironment();

  // Built outside the widget test's fake clock: the player starts periodic timers.
  late SubsonicService subsonic;
  late PlayerProvider player;
  late LibraryProvider library;

  setUp(() {
    subsonic = SubsonicService();
    player = PlayerProvider(
        subsonic,
        StorageService(),
        FakeCastService(),
        UpnpService(),
        MuslyAudioHandler(),
        JukeboxService(),
        TranscodingService());
    library = LibraryProvider(subsonic, MuslyAudioHandler());
  });

  tearDown(() => player.dispose());

  Future<_RecordingAuth> showTab(WidgetTester tester) async {
    final auth = _RecordingAuth(subsonic);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<SubsonicService>.value(value: subsonic),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<LibraryProvider>.value(value: library),
        ChangeNotifierProvider<PlayerProvider>.value(value: player),
        ChangeNotifierProvider<JukeboxService>.value(value: JukeboxService()),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SettingsServerTab()),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-lan-url')));
    await tester.pumpAndSettle();
    return auth;
  }

  // RD: the editor opens but Save is not passed on, so a LAN address typed in settings never takes effect.
  testWidgets('saving the LAN address passes it on', (tester) async {
    final auth = await showTab(tester);
    await tester.enterText(
        find.byKey(const ValueKey('lan-url-field')), 'http://nas:4533');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(auth.saved, ['http://nas:4533']);
  });

  // RD: Clear passes on the old address (or nothing), so a LAN address, once set, can never be removed.
  testWidgets('clearing passes on an empty address', (tester) async {
    final auth = await showTab(tester);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(auth.saved, ['']);
  });

  // RD: Cancel saves whatever was typed, so backing out of the editor still changes the route.
  testWidgets('cancelling changes nothing', (tester) async {
    final auth = await showTab(tester);
    await tester.enterText(
        find.byKey(const ValueKey('lan-url-field')), 'http://typo');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(auth.saved, isEmpty);
  });
}
