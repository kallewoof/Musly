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
import 'package:musly/widgets/now_playing/pick_reason_list.dart';

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
  bool smart = false;
  double? tasteSet;

  @override
  PickReason? get currentPickReason => reason;

  @override
  bool get isSmartShuffle => smart;

  @override
  Future<void> setSmartShuffleTaste(double taste) async => tasteSet = taste;
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
  late _ExplainingPlayer unexplained, explained, shuffling;
  setUp(() {
    unexplained = _ExplainingPlayer(null);
    explained = _ExplainingPlayer(mixPick);
    shuffling = _ExplainingPlayer(mixPick)..smart = true;
  });

  Future<void> pumpNowPlaying(WidgetTester tester, PlayerProvider player,
      {Size size = const Size(400, 800)}) async {
    tester.view.physicalSize = size;
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

  // RD: the list is left out of the Now Playing layout (or shown for every song), so a pick's reasons cannot be
  // seen, or an album's song shows reasons from a queue it is not in.
  testWidgets('Now Playing shows why a picked song was picked, and only then',
      (tester) async {
    await pumpNowPlaying(tester, unexplained);
    expect(find.byKey(const ValueKey('pick-reasons')), findsNothing);

    await pumpNowPlaying(tester, explained);
    expect(find.text('+.20: favourite'), findsOneWidget);
    expect(find.text('= .19: ranked by'), findsOneWidget);

    // Let the screen's delayed work (the title's marquee) run out after it is gone.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  // RD: the slider is left out of Now Playing, or shown when Smart Shuffle is off; or letting go of it does not
  // reach the player.
  testWidgets('Now Playing has the Smart Shuffle slider while it runs',
      (tester) async {
    await pumpNowPlaying(tester, explained);
    expect(find.byKey(const ValueKey('smart-shuffle-taste')), findsNothing);

    await pumpNowPlaying(tester, shuffling);
    await tester.drag(find.byKey(const ValueKey('smart-shuffle-taste')),
        const Offset(400, 0));
    await tester.pump();
    expect(shuffling.tasteSet, 1.0);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  // RD: the slider's extra row pushes the controls off a short landscape screen.
  testWidgets('the slider fits a landscape Now Playing', (tester) async {
    await pumpNowPlaying(tester, shuffling, size: const Size(850, 400));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('smart-shuffle-taste')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  // RD: the extra lines push the controls off a short landscape screen, an overflow that only shows for picked songs.
  testWidgets('the reasons fit a landscape Now Playing', (tester) async {
    await pumpNowPlaying(tester, explained, size: const Size(850, 400));

    expect(tester.takeException(), isNull);
    expect(find.text('+.20: favourite'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  // RD: the list drops the random part or the total, or loses a minus sign, so its lines do not add up to what
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

  // RD: a pick ranked with the slider off its middle shows only the draw, which did not decide its place; or the
  // line names the wrong end.
  test('says how the slider ranked a Smart Shuffle pick', () {
    ShufflePick at(double taste) => ShufflePick(
        completes: 0,
        skips: 0,
        starred: false,
        artistMean: null,
        draw: 0.4,
        typical: 0.5,
        taste: taste,
        rank: 2.4);

    expect(pickReasonLines(at(0.5), l10n).last,
        'drew .40 (typical .50); the highest draws play');
    expect(pickReasonLines(at(0.2), l10n).last,
        'ranked 2.40: the slider favours songs heard least');
    expect(pickReasonLines(at(0.8), l10n).last,
        'ranked 2.40: the slider favours songs liked most');
  });
}
