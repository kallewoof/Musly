import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musly/l10n/app_localizations.dart';
import 'package:musly/models/lyric_line.dart';
import 'package:musly/models/pick_reason.dart';
import 'package:musly/models/song.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/screens/player/now_playing_screen.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/jukebox_service.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/services/transcoding_service.dart';
import 'package:musly/services/upnp_service.dart';
import 'package:musly/widgets/now_playing/pick_reason_chip.dart';

import '../bootstrap.dart';
import '../test_helpers.dart';

class _ExplainingPlayer extends PlayerProvider {
  _ExplainingPlayer(this.reason)
      : super(
            SubsonicService(),
            StorageService(),
            FakeCastService(),
            UpnpService(),
            MuslyAudioHandler(),
            JukeboxService(),
            TranscodingService());

  final PickReason? reason;

  @override
  PickReason? get currentPickReason => reason;
}

void main() {
  initializeTestEnvironment();

  final l10n = lookupAppLocalizations(const Locale('en'));

  const mixPick = ScoredPick(terms: [
    ScoreTerm(ScoreFactor.plays, 0.04, 4),
    ScoreTerm(ScoreFactor.starred, 0.20),
    ScoreTerm(ScoreFactor.skips, -0.12, 2),
  ], jitter: 0.07);

  // Built outside the tests' fake time, where the player's own timer would be left pending.
  late _ExplainingPlayer unexplained, explained;
  setUp(() {
    unexplained = _ExplainingPlayer(null);
    explained = _ExplainingPlayer(mixPick);
  });

  Future<void> pumpNowPlaying(
      WidgetTester tester, PlayerProvider player) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    // A fresh tree: the app's providers are created once per tree, so the player would otherwise be the last one.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(createTestApp(
      playerProvider: player,
      child: NowPlayingScreen(
        song: Song(id: '1', title: 'Song 1', artist: 'Artist A'),
        image: const AssetImage('assets/logo.png'),
        title: 'Song 1',
        artist: 'Artist A',
        heroTag: 'test_hero',
        lyrics: [LyricLine(startTime: Duration.zero, text: 'Line')],
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
  }

  // RD: the chip is left out of the Now Playing layout (or shown for every song), so a pick's reasons cannot be seen,
  // or an album's song offers a "why?" with nothing behind it.
  testWidgets(
      'Now Playing offers "why?" for a picked song, and opens its reasons',
      (tester) async {
    await pumpNowPlaying(tester, unexplained);
    expect(find.byKey(const ValueKey('pick-reason-chip')), findsNothing);

    await pumpNowPlaying(tester, explained);
    await tester.tap(find.byKey(const ValueKey('pick-reason-chip')));
    // Now Playing animates for as long as it is open, so it never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Why this song'), findsOneWidget);
    expect(find.text('+.20: favourite'), findsOneWidget);

    // Let the screen's delayed work (the title's marquee) run out after it is gone.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  // RD: the sheet drops the random part or the total, or loses a minus sign, so its lines do not add up to what
  // ranked the song.
  test(
      'lists a mix pick largest part first, then the random part and the total',
      () {
    expect(pickReasonLines(mixPick, l10n), [
      '+.20: favourite',
      '-.12: skipped 2×',
      '+.04: played 4×',
      '+.07: random variety',
      '= .19: ranked by',
    ]);
  });

  // RD: the 0..1 clamp is not mentioned, so parts adding up to 1.10 sit above a total of 1.05 with nothing to say why.
  test('says when the parts add up beyond the range the score is kept in', () {
    const capped = ScoredPick(terms: [
      ScoreTerm(ScoreFactor.starred, 0.60),
      ScoreTerm(ScoreFactor.artist, 0.50),
    ], jitter: 0.05);

    expect(pickReasonLines(capped, l10n),
        containsAllInOrder(['score capped at 1.00', '= 1.05: ranked by']));
  });

  // RD: the draw and the typical value are swapped or dropped, so an exploring pick reads as a known favourite.
  test('shows a Smart Shuffle pick\'s evidence and its draw', () {
    const pick = ShufflePick(
        completes: 6,
        skips: 1,
        starred: true,
        artistMean: 0.8,
        draw: 0.91,
        typical: 0.62);

    expect(pickReasonLines(pick, l10n), [
      'finished 6×, skipped 1×',
      'favourite: counts as 3 finishes',
      "artist's other songs: 80% good, worth 2 listens",
      'drew .91 (typical .62); the highest draws play',
    ]);
  });
}
