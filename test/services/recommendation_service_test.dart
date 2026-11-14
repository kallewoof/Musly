import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/pick_reason.dart';
import 'package:musly/models/song.dart';
import 'package:musly/services/recommendation_service.dart';

import '../bootstrap.dart';

void main() {
  initializeTestEnvironment();

  late RecommendationService model;

  setUp(() async {
    model = RecommendationService();
    await model.initialize();
  });

  tearDown(() => model.dispose());

  // Starred, so a score stays clear of the 0..1 clamp and a penalty shows in full.
  Song song({int? plays, int? skips, int? completes}) => Song(
      id: 's1',
      title: 'T',
      starred: true,
      playCount: plays,
      skipCount: skips,
      completeCount: completes);

  // RD: the model still reads only this device's skip list, so songs skipped on the iPhone stay just as likely on Ubuntu.
  test('lowers the score of a song skipped on another device', () {
    expect(model.calculateSongScore(song(skips: 2)),
        lessThan(model.calculateSongScore(song())));
  });

  // RD: this device's skips, which the server counts as well, are added to the server's count, so each one counts twice.
  test('counts this device\'s skips once when the server holds them too',
      () async {
    await model.trackSkip(song());
    await model.trackSkip(song());

    expect(model.calculateSongScore(song(skips: 2)),
        closeTo(model.calculateSongScore(song()), 1e-9));
  });

  // RD: a song played on another device still gets the never-played bonus, so the mixes keep offering it as new.
  test('gives no never-played bonus to a song played on another device', () {
    expect(model.calculateSongScore(song(plays: 3)),
        lessThan(model.calculateSongScore(song())));
  });

  // RD: the server's completions are ignored, so songs heard to the end elsewhere rank no higher than songs abandoned there.
  test('ranks a song finished on other devices above one abandoned there', () {
    expect(model.calculateSongScore(song(plays: 4, completes: 4)),
        greaterThan(model.calculateSongScore(song(plays: 4, completes: 0))));
  });

  // RD: Smart Shuffle reads only the server's counts, which lag until the next library refresh, so a song skipped twice just now keeps coming back.
  test('reports this device\'s skips before the server\'s count catches up',
      () async {
    final s = Song(id: 's9', title: 'T', skipCount: 1, completeCount: 2);
    await model.trackSkip(s);
    await model.trackSkip(s);

    expect(model.listenOutcomes(s), (completes: 2, skips: 2));
  });

  // RD: a part is added to the score but left out of its breakdown (or entered with another value), so "why?" lists
  // parts that do not add up to what ranked the song.
  test('breaks a score into parts that add up to it', () {
    final s = Song(
        id: 's2',
        title: 'T',
        starred: true,
        userRating: 4,
        playCount: 4,
        completeCount: 3,
        skipCount: 2);

    final terms = model.scoreTerms(s);
    final sum = terms.fold(0.0, (sum, t) => sum + t.value);

    expect(sum, closeTo(model.calculateSongScore(s), 1e-9));
    expect(sum, inExclusiveRange(0, 1), reason: 'clear of the clamp');
  });

  // RD: a part is filed under another factor or with another input, so "why?" blames the skips on the play count.
  test('names each part with the input behind it', () {
    final terms = {
      for (final t in model.scoreTerms(Song(
          id: 's3',
          title: 'T',
          starred: true,
          playCount: 4,
          completeCount: 3,
          skipCount: 2)))
        t.factor: t
    };

    expect(terms[ScoreFactor.skips]?.count, 2);
    expect(terms[ScoreFactor.skips]!.value, isNegative);
    expect(terms[ScoreFactor.plays]?.count, 4);
    expect(terms[ScoreFactor.completion]?.count, 75);
    expect(terms[ScoreFactor.starred]!.value, isPositive);
    expect(terms.containsKey(ScoreFactor.unheard), isFalse);
  });

  // RD: the reasons kept for a mix are not the numbers it was ranked by (recomputed, or shared between mixes so one
  // mix's random part overwrites another's), so the totals shown contradict the mix's order.
  test('keeps, for each mix, the numbers that ranked it', () {
    final songs = [
      for (var i = 0; i < 12; i++)
        Song(
            id: 'm$i',
            title: 'T$i',
            starred: i.isEven,
            playCount: i,
            skipCount: i % 3)
    ];

    final first = model.getPersonalizedFeed(songs, limit: 12);
    final second = model.getPersonalizedFeed(songs, limit: 12);

    for (final mix in [first, second]) {
      final reasons = model.reasonsFor(mix);
      final totals = [for (final s in mix) (reasons[s.id] as ScoredPick).total];
      for (var i = 1; i < totals.length; i++) {
        expect(totals[i], lessThanOrEqualTo(totals[i - 1]));
      }
    }
    expect(model.reasonsFor(List.of(first)), isEmpty,
        reason: 'only the list the service returned');
  });
}
