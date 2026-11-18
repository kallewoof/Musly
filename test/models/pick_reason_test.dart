import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/pick_reason.dart';

void main() {
  PickReason roundTrip(PickReason r) => PickReason.fromJson(
      jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);

  // RD: a field is left out of the saved form or read back into the wrong one, so after a restart a song's
  // "why" shows other numbers than the ones that picked it.
  test('every kind of reason reads back as it was saved', () {
    final scored = roundTrip(const ScoredPick(terms: [
      ScoreTerm(ScoreFactor.plays, 0.18, 64),
      ScoreTerm(ScoreFactor.recentlyPlayed, -0.08),
    ], jitter: 0.03)) as ScoredPick;
    expect([
      for (final t in scored.terms) (t.factor, t.value, t.count)
    ], [
      (ScoreFactor.plays, 0.18, 64),
      (ScoreFactor.recentlyPlayed, -0.08, null)
    ]);
    expect(scored.jitter, 0.03);

    expect((roundTrip(const TopHitPick(12)) as TopHitPick).plays, 12);
    expect(roundTrip(const ListenAgainPick()), isA<ListenAgainPick>());

    final shuffle = roundTrip(const ShufflePick(
        completes: 3,
        skips: 1,
        starred: true,
        artistMean: 0.6,
        draw: 0.71,
        typical: 0.55)) as ShufflePick;
    expect((
      shuffle.completes,
      shuffle.skips,
      shuffle.starred,
      shuffle.artistMean,
      shuffle.draw,
      shuffle.typical
    ), (
      3,
      1,
      true,
      0.6,
      0.71,
      0.55
    ));
    final noArtist = roundTrip(const ShufflePick(
        completes: 0,
        skips: 0,
        starred: false,
        artistMean: null,
        draw: 1,
        typical: 0.5)) as ShufflePick;
    expect((noArtist.artistMean, noArtist.draw), (null, 1.0));

    final radio = roundTrip(
            const RadioPick(seedTitle: 'Song 1', source: RadioSource.genre))
        as RadioPick;
    expect((radio.seedTitle, radio.source), ('Song 1', RadioSource.genre));
  });
}
