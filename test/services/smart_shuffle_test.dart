import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/pick_reason.dart';
import 'package:musly/models/song.dart';
import 'package:musly/services/smart_shuffle.dart';

void main() {
  Song song(String id, {String? artist, bool starred = false}) =>
      Song(id: id, title: id, artist: artist, starred: starred);

  /// How often each song is picked first over [trials] seeded draws.
  Map<String, int> firstPicks(
      List<Song> songs, Map<String, ListenOutcomes> history,
      {int trials = 2000}) {
    final shuffle = SmartShuffle(random: Random(7));
    final counts = <String, int>{};
    for (var i = 0; i < trials; i++) {
      final first = shuffle
          .pick(songs, 1,
              exclude: const {},
              outcomes: (s) => history[s.id] ?? (completes: 0, skips: 0))
          .single;
      counts[first.id] = (counts[first.id] ?? 0) + 1;
    }
    return counts;
  }

  // RD: a slip in the Beta or gamma sampler skews every draw (toward one value, or too narrow), so the history barely changes what plays.
  test('draws chances whose average and spread follow the evidence', () {
    final shuffle = SmartShuffle(random: Random(1));
    for (final (a, b) in [(1.0, 1.0), (8.0, 2.0), (0.5, 0.5), (2.0, 30.0)]) {
      final draws = [for (var i = 0; i < 20000; i++) shuffle.sampleBeta(a, b)];
      final mean = draws.reduce((x, y) => x + y) / draws.length;
      final variance =
          draws.map((x) => (x - mean) * (x - mean)).reduce((x, y) => x + y) /
              draws.length;
      expect(mean, closeTo(a / (a + b), 0.01), reason: 'mean of Beta($a,$b)');
      expect(
          variance, closeTo(a * b / ((a + b) * (a + b) * (a + b + 1)), 0.005),
          reason: 'variance of Beta($a,$b)');
    }
  });

  // RD: completions and skips are swapped or ignored, so Smart Shuffle plays skipped songs as readily as favourites.
  test('plays songs heard through far more than songs skipped', () {
    final counts = firstPicks([
      song('loved'),
      song('skipped')
    ], {
      'loved': (completes: 6, skips: 0),
      'skipped': (completes: 0, skips: 6),
    });
    expect(counts['loved'] ?? 0, greaterThan(1900));
  });

  // RD: an unheard song gets no chance against a favourite, so nothing new is ever played and the model never learns.
  test('still plays unheard songs next to a favourite', () {
    final songs = [song('loved'), for (var i = 0; i < 5; i++) song('new$i')];
    final counts = firstPicks(songs, {'loved': (completes: 6, skips: 1)});
    final unheard = 2000 - (counts['loved'] ?? 0);
    expect(counts['loved'] ?? 0, greaterThan(2000 ~/ 6),
        reason: 'the favourite beats an even share');
    expect(unheard, greaterThan(200), reason: 'new songs still get played');
  });

  // RD: an unheard song ignores its artist's record, so exploring plays an often-skipped artist as readily as a loved one.
  test('tries unheard songs by a loved artist before those by a skipped one',
      () {
    final songs = [
      song('loved-old', artist: 'A'),
      song('loved-new', artist: 'A'),
      song('skipped-old', artist: 'B'),
      song('skipped-new', artist: 'B'),
    ];
    final shuffle = SmartShuffle(random: Random(3));
    var lovedFirst = 0;
    for (var i = 0; i < 2000; i++) {
      final first = shuffle
          .pick(songs, 1,
              exclude: {'loved-old', 'skipped-old'},
              outcomes: (s) => switch (s.id) {
                    'loved-old' => (completes: 8, skips: 0),
                    'skipped-old' => (completes: 0, skips: 8),
                    _ => (completes: 0, skips: 0),
                  })
          .single;
      if (first.id == 'loved-new') lovedFirst++;
    }
    expect(lovedFirst, greaterThan(1300));
  });

  // RD: a star is ignored, so a song starred but never heard to its end plays no more often than any other.
  test('counts a star in a song\'s favour', () {
    final counts =
        firstPicks([song('starred', starred: true), song('plain')], const {});
    expect(counts['starred'] ?? 0, greaterThan(1300));
  });

  // RD: recently played or already queued songs are picked again, so the queue repeats itself within minutes.
  test('never picks an excluded song, nor one twice', () {
    final songs = [for (var i = 0; i < 6; i++) song('s$i', artist: 'A$i')];
    final picks = SmartShuffle(random: Random(5)).pick(songs, 10,
        exclude: {'s0', 's1'}, outcomes: (_) => (completes: 0, skips: 0));
    expect(picks.map((s) => s.id).toSet(), {'s2', 's3', 's4', 's5'});
    expect(picks.length, 4);
  });

  // RD: the artist gap is dropped, or never relaxed, so the queue plays one artist back to back, or runs dry when the library has few artists.
  test('keeps an artist\'s songs apart, and fills up when it cannot', () {
    final songs = [
      for (var i = 0; i < 4; i++) song('a$i', artist: 'A'),
      for (var i = 0; i < 4; i++) song('b$i', artist: 'B'),
      for (var i = 0; i < 4; i++) song('c$i', artist: 'C'),
      for (var i = 0; i < 4; i++) song('d$i', artist: 'D'),
    ];
    final picks = SmartShuffle(random: Random(9)).pick(songs, 4,
        exclude: const {},
        outcomes: (_) => (completes: 0, skips: 0),
        recentArtists: ['A']);
    final artists = picks.map((s) => s.artist).toList();
    expect(artists.toSet().length, 4, reason: 'four artists in four picks');
    expect(artists.first, isNot('A'), reason: 'A was just queued');

    final oneArtist = [for (var i = 0; i < 5; i++) song('x$i', artist: 'X')];
    expect(
        SmartShuffle(random: Random(9))
            .pick(oneArtist, 5,
                exclude: const {}, outcomes: (_) => (completes: 0, skips: 0))
            .length,
        5);
  });

  // RD: the draw kept for "why?" is not the one that ranked the pick, or its typical value comes from other parameters,
  // so the shown numbers did not decide what played.
  test('records the draw that ranked each pick and the evidence behind it', () {
    final reasons = <String, PickReason>{};
    final songs = [
      song('loved', starred: true),
      for (var i = 0; i < 9; i++) song('s$i'),
    ];

    final picked = SmartShuffle(random: Random(3)).pick(songs, 10,
        exclude: const {},
        outcomes: (s) => s.id == 'loved'
            ? (completes: 6, skips: 1)
            : (completes: 0, skips: 0),
        reasons: reasons);

    final draws = [for (final s in picked) (reasons[s.id] as ShufflePick).draw];
    for (var i = 1; i < draws.length; i++) {
      expect(draws[i], lessThanOrEqualTo(draws[i - 1]));
    }
    final loved = reasons['loved'] as ShufflePick;
    expect((loved.completes, loved.skips, loved.starred), (6, 1, true));
    expect(loved.artistMean, isNull);
    // Beta(6 + 3 for the star + 1, 1 + 1): no artist, so the prior is 0.5 of 2 listens.
    expect(loved.typical, closeTo(10 / 12, 1e-9));
  });

  // RD: the artist's record is computed but not kept, or kept with this song's own listens in it.
  test('records the artist record a song started from', () {
    final reasons = <String, PickReason>{};
    SmartShuffle(random: Random(3)).pick(
        [song('a', artist: 'X'), song('b', artist: 'X')], 2,
        exclude: const {},
        outcomes: (s) =>
            s.id == 'a' ? (completes: 4, skips: 0) : (completes: 0, skips: 2),
        reasons: reasons);

    // b's artist record is a's: (4 + 1) / (4 + 0 + 2).
    expect((reasons['b'] as ShufflePick).artistMean, closeTo(5 / 6, 1e-9));
  });

  // RD: the placeholder of untagged songs counts as an artist, so each untagged song starts from the record of all
  // the others.
  test('gives songs without an artist tag no shared artist record', () {
    final reasons = <String, PickReason>{};
    SmartShuffle(random: Random(3)).pick(
        [
          song('a', artist: Song.unknownArtist),
          song('b', artist: Song.unknownArtist)
        ],
        2,
        exclude: const {},
        outcomes: (s) =>
            s.id == 'a' ? (completes: 4, skips: 0) : (completes: 0, skips: 0),
        reasons: reasons);

    expect((reasons['b'] as ShufflePick).artistMean, isNull);
  });

  // RD: the artist gap treats the placeholder as one artist, so untagged songs the user loves are held back behind
  // songs they skip.
  test('does not space songs without an artist tag apart', () {
    final picked = SmartShuffle(random: Random(3)).pick(
        [
          song('loved1', artist: Song.unknownArtist),
          song('loved2', artist: Song.unknownArtist),
          song('skipped', artist: 'Artist A'),
        ],
        3,
        exclude: const {},
        outcomes: (s) => s.id == 'skipped'
            ? (completes: 0, skips: 50)
            : (completes: 50, skips: 0));

    expect(picked[2].id, 'skipped');
  });

  /// The first [count] picks with the slider at [taste], over the seeds [seeds].
  List<List<String>> picksAt(
          double taste, List<Song> songs, Map<String, ListenOutcomes> history,
          {int count = 3, int seeds = 20}) =>
      [
        for (var seed = 0; seed < seeds; seed++)
          SmartShuffle(random: Random(seed))
              .pick(songs, count,
                  exclude: const {},
                  outcomes: (s) => history[s.id] ?? (completes: 0, skips: 0),
                  taste: taste)
              .map((s) => s.id)
              .toList(),
      ];

  // RD: the left end only nudges the draw, so with a large unheard backlog favourites still crowd out new songs;
  // or it boosts heard songs as much as unheard ones.
  test('at the far left, plays only songs never heard while there are any', () {
    final songs = [
      for (var i = 0; i < 4; i++) song('loved$i', artist: 'A$i'),
      for (var i = 0; i < 12; i++) song('new$i', artist: 'N$i'),
    ];
    final history = {
      for (var i = 0; i < 4; i++) 'loved$i': (completes: 8, skips: 0)
    };

    for (final picks in picksAt(0, songs, history, count: 10)) {
      expect(picks.where((id) => id.startsWith('loved')), isEmpty);
    }
  });

  // RD: novelty ignores how often a heard song was heard, so the left end plays a song heard many times as
  // readily as one heard once.
  test('left of the middle, prefers songs heard less', () {
    final songs = [song('once', artist: 'A'), song('often', artist: 'B')];
    final history = {
      'once': (completes: 1, skips: 0),
      'often': (completes: 9, skips: 0),
    };

    final firsts = picksAt(0, songs, history, count: 1, seeds: 200);

    expect(firsts.where((p) => p.single == 'once').length, greaterThan(150));
  });

  // RD: the right end still ranks by the random draw, so it keeps exploring unheard songs instead of playing
  // the favourites; or it ranks by the evidence backwards.
  test('at the far right, plays the songs liked most, in order', () {
    final songs = [
      song('loved', artist: 'A', starred: true),
      song('liked', artist: 'B'),
      song('skipped', artist: 'C'),
      for (var i = 0; i < 10; i++) song('new$i', artist: 'N$i'),
    ];
    final history = {
      'loved': (completes: 6, skips: 0),
      'liked': (completes: 4, skips: 1),
      'skipped': (completes: 0, skips: 5),
    };

    for (final picks in picksAt(1, songs, history, count: 2)) {
      expect(picks, ['loved', 'liked']);
    }
  });

  // RD: the slider's middle changes the ranking, so Smart Shuffle with the slider untouched no longer behaves as
  // it did; or the recorded rank is not what ranked the song.
  test('in the middle, ranks by the draw alone', () {
    final reasons = <String, PickReason>{};
    final songs = [for (var i = 0; i < 8; i++) song('s$i', artist: 'A$i')];
    SmartShuffle(random: Random(4)).pick(songs, 8,
        exclude: const {},
        outcomes: (_) => (completes: 1, skips: 0),
        reasons: reasons);

    final picks = reasons.values.cast<ShufflePick>().toList();
    expect(picks.every((p) => p.rank == p.draw), isTrue);
    final ranks = [for (final p in picks) p.rank];
    expect(ranks, [...ranks]..sort((a, b) => b.compareTo(a)));
  });
}
