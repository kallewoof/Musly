import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musly/l10n/app_localizations.dart';
import 'package:musly/models/song.dart';
import 'package:musly/providers/library_provider.dart';
import 'package:musly/screens/media/taste_map_screen.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/recommendation_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/widgets/taste_map/taste_map_chart.dart';
import 'package:provider/provider.dart';

import '../bootstrap.dart';

class _Library extends LibraryProvider {
  _Library(this.songs) : super(SubsonicService(), MuslyAudioHandler());
  final List<Song> songs;
  @override
  List<Song> get cachedAllSongs => songs;
}

void main() {
  initializeTestEnvironment();

  final now = DateTime.utc(2026, 11, 26, 12);
  const size = Size(400, 600);
  TasteMapPoint point(String id, double liking, {DateTime? played}) =>
      TasteMapPoint(Song(id: id, title: id, played: played), liking);

  group('geometry', () {
    // RD: the time axis is reversed or anchored wrongly, so the song played just now sits at the left with
    // the songs played longest ago.
    test('songs played run from the oldest play (left) to now (right)', () {
      final g = TasteMapGeometry([
        point('old', 0.5, played: DateTime.utc(2026, 11, 12)),
        point('mid', 0.5, played: DateTime.utc(2026, 11, 19, 6)),
        point('new', 0.5, played: now),
      ], size, now: now);
      final x = {for (final (p, o) in g.placed) p.song.id: o.dx};

      expect(x['old'], closeTo(g.plot.left, 0.01));
      expect(x['new'], closeTo(g.plot.right, 0.01));
      expect(x['mid'], closeTo((g.plot.left + g.plot.right) / 2, 1));
    });

    // RD: the liking axis is upside down, so the songs the user likes most sit at the bottom.
    test('liked songs sit higher, neutral in the middle', () {
      final g = TasteMapGeometry([
        point('liked', 0.9, played: now),
        point('disliked', 0.2, played: now),
      ], size, now: now);
      final y = {for (final (p, o) in g.placed) p.song.id: o.dy};

      expect(y['liked']!, lessThan(g.yOf(0.5)));
      expect(y['disliked']!, greaterThan(g.yOf(0.5)));
      expect(g.yOf(0.5), closeTo(g.plot.center.dy, 0.01));
    });

    // RD: never-played songs are drawn as blocks (thousands, unreadable) or dropped, so the lane is empty
    // or the plot is buried; or they are counted in the wrong band of liking.
    test('songs never played are counted in the lane by their liking', () {
      final g = TasteMapGeometry([
        point('a', 0.51),
        point('b', 0.52),
        point('c', 0.9),
        point('played', 0.9, played: now),
      ], size, now: now);

      expect(g.placed.map((e) => e.$1.song.id), ['played']);
      final counted = {
        for (final b in g.lane)
          if (b.songs.isNotEmpty) b.index: b.songs.length
      };
      expect(counted, {
        TasteMapGeometry.bandOf(0.51): 2,
        TasteMapGeometry.bandOf(0.9): 1,
      });
    });

    // RD: the lane's bars scale to a band that dwarfs the rest (the songs with no history at neutral), so
    // every other band is a sliver; or the outlier is drawn to the reduced scale as if it were no bigger.
    test('a band that dwarfs the rest is broken, the others scale to the next',
        () {
      final g = TasteMapGeometry([
        for (var i = 0; i < 100; i++) point('n$i', 0.5),
        for (var i = 0; i < 10; i++) point('s$i', 0.3),
        for (var i = 0; i < 5; i++) point('f$i', 0.9),
      ], size, now: now);
      LaneBand band(double liking) => g.lane[TasteMapGeometry.bandOf(liking)];

      expect(g.isBroken(band(0.5)), isTrue);
      expect(g.isBroken(band(0.3)), isFalse);
      expect(g.barOf(band(0.3))!.width, closeTo(g.laneRect.width, 0.01));
      expect(g.barOf(band(0.9))!.width, closeTo(g.laneRect.width / 2, 0.01));
    });

    // RD: a tap selects a song far from it, or nothing near a block, so the song under the finger is not
    // the one shown.
    test('a tap selects the nearest block within reach, or a lane band', () {
      final g = TasteMapGeometry([
        point('a', 0.9, played: DateTime.utc(2026, 11, 12)),
        point('b', 0.9, played: now),
        point('lane', 0.3),
      ], size, now: now);
      final b = g.placed.firstWhere((e) => e.$1.song.id == 'b').$2;

      expect(g.hit(b.translate(-5, 3))?.song.id, 'b');
      expect(g.hit(b.translate(-60, 0)), isNull);
      expect(g.hitLane(Offset(10, g.yOf(0.31)))?.songs.single.song.id, 'lane');
      expect(g.hitLane(Offset(10, g.yOf(0.8))), isNull);
    });
  });

  // RD: the legend's steps and the blocks' steps disagree, so a song played once is coloured as one played
  // 2-3 times. The steps are the legend's contract.
  test('play counts fall into the legend\'s steps', () {
    expect([0, 1, 2, 3, 4, 7, 8, 50].map(playsStep), [0, 1, 2, 2, 3, 3, 4, 4]);
    expect(playsStepLabels, hasLength(playsRampLight.length));
    expect(playsStepLabels, hasLength(playsRampDark.length));
  });

  // RD: the map's liking is computed apart from Smart Shuffle (a star ignored, skips not counted), so it
  // shows a taste the shuffle does not act on.
  testWidgets('songs are ordered by what Smart Shuffle believes',
      (tester) async {
    final songs = [
      Song(id: 'skipped', title: 'Skipped', skipCount: 3, played: now),
      Song(id: 'plain', title: 'Plain'),
      Song(id: 'starred', title: 'Starred', starred: true),
      Song(id: 'finished', title: 'Finished', completeCount: 1, played: now),
    ];
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryProvider>.value(value: _Library(songs)),
        ChangeNotifierProvider<RecommendationService>.value(
            value: RecommendationService()),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TasteMapScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Show as list'));
    await tester.pumpAndSettle();

    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text).data)
        .toList();
    expect(titles, ['Starred', 'Finished', 'Plain', 'Skipped']);
  });
}
