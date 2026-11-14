import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/pick_reason.dart';
import '../models/song.dart';

/// How a user's listens to a song ended: heard through, or skipped early.
typedef ListenOutcomes = ({int completes, int skips});

/// Picks songs for Smart Shuffle: an endless queue of what the user is likely to enjoy, mixed with music they
/// have not heard yet, by Thompson sampling.
///
/// Each song's chance of a good listen is a Beta distribution over its completions (a star counts as
/// [starWeight] of them) and skips. A song with little history starts from its artist's record, worth
/// [priorStrength] listens, so its distribution is wide: it sometimes draws high enough to be played, less
/// often as listens narrow it. Every refill draws afresh, so the queue follows what the counts have learnt.
class SmartShuffle {
  SmartShuffle({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// How many listens an artist's record counts as, for a song of theirs.
  static const double priorStrength = 2.0;

  /// How many completions a star counts as.
  static const double starWeight = 3.0;

  /// An artist's songs are at least this many picks apart, when the library allows it.
  static const int artistGap = 3;

  /// Up to [count] songs from [candidates], never one in [exclude]. [recentArtists] are the artists just
  /// queued, newest last, so the gap holds across refills. Each pick's [ShufflePick] goes into [reasons].
  List<Song> pick(
    List<Song> candidates,
    int count, {
    required Set<String> exclude,
    required ListenOutcomes Function(Song) outcomes,
    List<String?> recentArtists = const [],
    Map<String, PickReason>? reasons,
  }) {
    final counts = <String, ListenOutcomes>{};
    final evidence = <String, ({double good, double bad})>{};
    final byArtist = <String, ({double good, double bad})>{};
    for (final song in candidates) {
      final o = outcomes(song);
      counts[song.id] = o;
      final e = (
        good: o.completes + (song.starred == true ? starWeight : 0.0),
        bad: o.skips.toDouble()
      );
      evidence[song.id] = e;
      final artist = song.artist;
      if (artist != null) {
        final a = byArtist[artist] ?? (good: 0.0, bad: 0.0);
        byArtist[artist] = (good: a.good + e.good, bad: a.bad + e.bad);
      }
    }

    final drawn = <(Song, ShufflePick)>[];
    for (final song in candidates) {
      if (exclude.contains(song.id)) continue;
      final e = evidence[song.id]!;
      final a = song.artist == null ? null : byArtist[song.artist];
      // The artist's record without this song, smoothed so an artist with one listen is not certain.
      final mean = a == null
          ? 0.5
          : (a.good - e.good + 1) / (a.good - e.good + a.bad - e.bad + 2);
      final alpha = e.good + priorStrength * mean;
      final beta = e.bad + priorStrength * (1 - mean);
      final o = counts[song.id]!;
      drawn.add((
        song,
        ShufflePick(
          completes: o.completes,
          skips: o.skips,
          starred: song.starred == true,
          artistMean: a == null ? null : mean,
          draw: _beta(alpha, beta),
          typical: alpha / (alpha + beta),
        )
      ));
    }
    drawn.sort((x, y) => y.$2.draw.compareTo(x.$2.draw));

    final picked = <Song>[];
    final taken = <String>{};
    final lastArtists = List<String?>.of(recentArtists);
    bool spaced(Song s) =>
        s.artist == null ||
        !lastArtists.reversed.take(artistGap).contains(s.artist);
    for (final strict in [true, false]) {
      for (final (song, reason) in drawn) {
        if (picked.length >= count) return picked;
        if (taken.contains(song.id) || (strict && !spaced(song))) continue;
        picked.add(song);
        reasons?[song.id] = reason;
        taken.add(song.id);
        lastArtists.add(song.artist);
      }
    }
    return picked;
  }

  @visibleForTesting
  double sampleBeta(double a, double b) => _beta(a, b);

  double _beta(double a, double b) {
    final x = _gamma(a);
    final y = _gamma(b);
    return x / (x + y);
  }

  /// Marsaglia and Tsang's method; a shape below 1 is boosted by 1 and scaled back.
  double _gamma(double shape) {
    if (shape < 1) {
      return _gamma(shape + 1) * pow(_random.nextDouble(), 1 / shape);
    }
    final d = shape - 1 / 3;
    final c = 1 / sqrt(9 * d);
    while (true) {
      double x, v;
      do {
        x = _normal();
        v = 1 + c * x;
      } while (v <= 0);
      v = v * v * v;
      final u = _random.nextDouble();
      if (u < 1 - 0.0331 * x * x * x * x) return d * v;
      if (log(u) < 0.5 * x * x + d * (1 - v + log(v))) return d * v;
    }
  }

  double _normal() {
    final u1 = 1 - _random.nextDouble();
    final u2 = _random.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }
}
