/// Why a song is in the queue: the numbers that put it there, kept from the moment it was picked, so they
/// still explain the pick after later listens have moved the scores.
sealed class PickReason {
  const PickReason();

  /// Kept with the saved queue, so a queue restored at launch still explains its songs.
  Map<String, Object?> toJson() => switch (this) {
        ScoredPick(:final terms, :final jitter) => {
            'kind': 'scored',
            'terms': [
              for (final t in terms) [t.factor.name, t.value, t.count],
            ],
            'jitter': jitter,
          },
        TopHitPick(:final plays) => {'kind': 'topHit', 'plays': plays},
        ListenAgainPick() => {'kind': 'listenAgain'},
        ShufflePick p => {
            'kind': 'shuffle',
            'completes': p.completes,
            'skips': p.skips,
            'starred': p.starred,
            'artistMean': p.artistMean,
            'draw': p.draw,
            'typical': p.typical,
          },
        RadioPick p => {
            'kind': 'radio',
            'seedTitle': p.seedTitle,
            'source': p.source.name,
          },
      };

  /// Reads what [toJson] wrote; throws on anything else.
  static PickReason fromJson(Map<String, dynamic> j) {
    double d(Object? v) => (v as num).toDouble();
    return switch (j['kind']) {
      'scored' => ScoredPick(
          terms: [
            for (final t in j['terms'] as List)
              ScoreTerm(ScoreFactor.values.byName(t[0] as String), d(t[1]),
                  t[2] as num?),
          ],
          jitter: d(j['jitter']),
        ),
      'topHit' => TopHitPick(j['plays'] as int),
      'listenAgain' => const ListenAgainPick(),
      'shuffle' => ShufflePick(
          completes: j['completes'] as int,
          skips: j['skips'] as int,
          starred: j['starred'] as bool,
          artistMean: j['artistMean'] == null ? null : d(j['artistMean']),
          draw: d(j['draw']),
          typical: d(j['typical']),
        ),
      'radio' => RadioPick(
          seedTitle: j['seedTitle'] as String,
          source: RadioSource.values.byName(j['source'] as String),
        ),
      final kind => throw FormatException('unknown pick reason kind: $kind'),
    };
  }
}

/// The parts of a recommendation score (`RecommendationService.scoreTerms`).
enum ScoreFactor {
  artist,
  genre,
  album,
  artistRating,
  genreRating,
  completion,
  plays,
  unheard,
  hourOfDay,
  profileRating,
  songRating,
  starred,
  skips,
  recentlyPlayed,
  genreAtThisHour,
}

/// One part of a score: [value] is what it added (negative: took away). [count] is the input behind it
/// where one number says it: plays, skips, songs since it last played, a percentage, a rating.
class ScoreTerm {
  const ScoreTerm(this.factor, this.value, [this.count]);

  final ScoreFactor factor;
  final double value;
  final num? count;
}

/// A song from a home-screen mix, ranked by its score plus [jitter], the random amount that keeps mixes
/// from repeating.
class ScoredPick extends PickReason {
  const ScoredPick({required this.terms, required this.jitter});

  final List<ScoreTerm> terms;
  final double jitter;

  double get termSum => terms.fold(0.0, (sum, t) => sum + t.value);

  /// What the mix was ranked by: the score, which is kept within 0 to 1, plus the jitter.
  double get total => termSum.clamp(0.0, 1.0) + jitter;
}

/// A song in "Your Top Hits", which ranks by play count first.
class TopHitPick extends PickReason {
  const TopHitPick(this.plays);

  final int plays;
}

/// A song in "Listen Again", the songs played most recently.
class ListenAgainPick extends PickReason {
  const ListenAgainPick();
}

/// A Smart Shuffle pick: the evidence that shaped the song's Beta distribution, and the value drawn from
/// it. The songs with the highest draws are played, so a [draw] well above [typical] is the shuffle
/// exploring, and a high [typical] is a song the user is known to like.
class ShufflePick extends PickReason {
  const ShufflePick({
    required this.completes,
    required this.skips,
    required this.starred,
    required this.artistMean,
    required this.draw,
    required this.typical,
  });

  final int completes;
  final int skips;
  final bool starred;

  /// The artist's record from their other songs, smoothed; null when the song has no artist.
  final double? artistMean;
  final double draw;

  /// The distribution's mean: what draws for this song average.
  final double typical;
}

/// Where a radio's songs came from: the server's similar songs, or the fallback used when it had none.
enum RadioSource { similar, genre, artistTopSongs, artistSearch, random }

/// A song a radio added, from [seedTitle] the song it was seeded with.
class RadioPick extends PickReason {
  const RadioPick({required this.seedTitle, required this.source});

  final String seedTitle;
  final RadioSource source;
}
