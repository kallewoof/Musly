import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
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
}
