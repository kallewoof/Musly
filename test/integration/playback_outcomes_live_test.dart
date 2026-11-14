import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/models.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_config.dart';

/// Playback reports against a real server that counts their outcomes. Skipped without a configured server
/// (test/test_config.dart) or one without the unimousePlaybackOutcomes extension. It adds a skip and a
/// completion to one song of that user.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // RD: Musly's reportPlayback request does not match what the server reads (parameter names, auth,
  // ignoreScrobble), or its song parser misses the counts, so no skip or completion is ever counted or seen.
  test(
      'a skip and a completion reported by Musly come back as the song\'s counts',
      () async {
    if (!TestConfig.isConfigured) {
      markTestSkipped('No Navidrome server configured');
      return;
    }
    SharedPreferences.setMockInitialValues({});
    await StorageService().init();
    final c = TestConfig.configJson;
    final service = SubsonicService();
    await service.configure(ServerConfig(
      serverUrl: TestConfig.serverUrl,
      username: c['username'] as String,
      password: c['password'] as String,
    ));
    if (!(await service.openSubsonicExtensions())
        .contains('unimousePlaybackOutcomes')) {
      markTestSkipped('The server does not count playback outcomes');
      return;
    }
    final song = (await service.getRandomSongs(size: 10))
        .firstWhere((s) => (s.duration ?? 0) >= 2);
    Future<Song> current() async => (await service.getAlbumSongs(song.albumId!))
        .firstWhere((s) => s.id == song.id);
    final before = await current();

    await service.reportPlayback(song.id, 'starting', Duration.zero);
    await service.reportPlayback(song.id, 'stopped', Duration.zero);
    await service.reportPlayback(song.id, 'starting', Duration.zero);
    await service.reportPlayback(
        song.id, 'stopped', Duration(seconds: song.duration!));
    final after = await current();

    expect((after.skipCount ?? 0) - (before.skipCount ?? 0), 1);
    expect((after.completeCount ?? 0) - (before.completeCount ?? 0), 1);
    expect(after.playCount ?? 0, before.playCount ?? 0,
        reason: 'plays are submitted by scrobble; a report must not add one');
  });
}
