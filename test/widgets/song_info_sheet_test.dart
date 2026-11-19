import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musly/l10n/app_localizations.dart';
import 'package:musly/models/pick_reason.dart';
import 'package:musly/models/song.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/jukebox_service.dart';
import 'package:musly/services/recommendation_service.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/services/transcoding_service.dart';
import 'package:musly/services/upnp_service.dart';
import 'package:musly/widgets/modals/song_info_sheet.dart';
import 'package:musly/widgets/now_playing/now_playing_more_menu.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bootstrap.dart';
import '../test_helpers.dart';

/// A server whose song has the counts in [fresh], or that cannot be reached.
class _Server extends SubsonicService {
  Song? fresh;

  @override
  Future<({Song song, List<String> composers})> getSongWithComposers(
      String id) async {
    if (fresh == null) throw Exception('connection refused');
    return (song: fresh!, composers: const <String>[]);
  }
}

class _Player extends PlayerProvider {
  _Player()
      : super(
            SubsonicService(),
            StorageService(),
            FakeCastService(),
            UpnpService(),
            MuslyAudioHandler(),
            JukeboxService(),
            TranscodingService());

  Song? playing;
  PickReason? reason;

  @override
  Song? get currentSong => playing;

  @override
  PickReason? pickReasonOf(String songId) => reason;
}

void main() {
  initializeTestEnvironment();

  // As a list shows it: the counts it was loaded with.
  final listed =
      Song(id: 's1', title: 'Song 1', artist: 'Artist A', playCount: 0);
  final current = Song(
      id: 's1',
      title: 'Song 1',
      artist: 'Artist A',
      playCount: 3,
      completeCount: 2,
      skipCount: 1,
      starred: true,
      userRating: 4,
      played: DateTime.utc(2026, 11, 18, 10, 30),
      suffix: 'mp3',
      bitRate: 192,
      duration: 245);

  late _Server server;
  late _Player player;
  late RecommendationService taste;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = _Server();
    player = _Player();
    taste = RecommendationService();
    await taste.initialize();
  });

  tearDown(() => taste.dispose());

  Widget app(Widget child) => MultiProvider(
        providers: [
          Provider<SubsonicService>.value(value: server),
          ChangeNotifierProvider<PlayerProvider>.value(value: player),
          ChangeNotifierProvider<RecommendationService>.value(value: taste),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      );

  String value(WidgetTester tester, String key) => tester
      .widgetList<Text>(find.descendant(
          of: find.byKey(ValueKey('song-info-$key')),
          matching: find.byType(Text)))
      .last
      .data!;

  // RD: the sheet shows the counts the list was loaded with, so a song played since shows its old count; or a
  // field reads another field's value.
  testWidgets(
      "shows the server's current counts, this device's, and why it is queued",
      (tester) async {
    server.fresh = current;
    // Outside the fake clock: the taste model saves on a timer after a skip.
    await tester.runAsync(() => taste.trackSkip(listed));
    player.reason = const ShufflePick(
        plays: 3,
        completes: 2,
        skips: 1,
        starred: true,
        artistMean: null,
        draw: 0.8,
        typical: 0.7);

    await tester.pumpWidget(app(SongInfoSheet(song: listed)));
    await tester.pumpAndSettle();

    expect([
      for (final k in ['plays', 'finished', 'skipped', 'favourite', 'rating'])
        value(tester, k)
    ], [
      '3',
      '2',
      '1',
      'yes',
      '4/5'
    ]);
    expect(value(tester, 'last-played'), contains('2026'));
    expect(value(tester, 'device-skipped'), '1');
    expect(value(tester, 'format'), 'MP3, 192 kbps');
    expect(value(tester, 'length'), '4:05');
    expect(find.text('played 3× (all devices)'), findsOneWidget);
  });

  // RD: a failed load is swallowed, so out-of-date counts are shown as if current; or the sheet stays empty.
  testWidgets(
      'says when the server cannot be reached, showing the counts it has',
      (tester) async {
    await tester.pumpWidget(app(SongInfoSheet(song: listed)));
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
    expect(value(tester, 'plays'), '0');
    expect(find.byKey(const ValueKey('song-info-why')), findsNothing);
  });

  // RD: the entry is left out of the Now Playing menu, so on the phone there is no way to see a song's numbers.
  testWidgets('the Now Playing menu opens the song info', (tester) async {
    server.fresh = current;
    player.playing = listed;
    await tester.pumpWidget(app(Builder(
      builder: (context) => TextButton(
        onPressed: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => const NowPlayingMoreMenu()),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('song-info-entry')));
    await tester.pumpAndSettle();

    expect(find.byType(SongInfoSheet), findsOneWidget);
  });
}
