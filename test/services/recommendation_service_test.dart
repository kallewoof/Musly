import 'package:flutter_test/flutter_test.dart';
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
}
