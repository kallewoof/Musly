import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/models.dart';
import 'package:musly/services/play_queue_sync.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_config.dart';

/// Play-queue sync against a real server: two installs, one stopping and the other resuming. Skipped
/// without a configured server (test/test_config.dart). It overwrites that user's saved play queue.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(SubsonicService, PlayQueueSync)> install() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().init();
    final c = TestConfig.configJson;
    final service = SubsonicService();
    await service.configure(ServerConfig(
      serverUrl: TestConfig.serverUrl,
      username: c['username'] as String,
      password: c['password'] as String,
    ));
    return (service, PlayQueueSync(service));
  }

  // RD: the server rejects or misreads the form POST (auth in the body, repeated ids), so every push fails
  // quietly and no device ever sees another's stop position.
  test(
      'a queue saved by one install is offered to another at its song and position',
      () async {
    if (!TestConfig.isConfigured) {
      markTestSkipped('No Navidrome server configured');
      return;
    }
    final (phone, phoneSync) = await install();
    final songs = await phone.getRandomSongs(size: 3);
    expect(songs.length, greaterThanOrEqualTo(2),
        reason: 'the library needs at least two songs');

    phoneSync.markChanged(songs, 1, const Duration(milliseconds: 61234));
    await phoneSync.flush();
    expect(phoneSync.hasUnsentChange, isFalse, reason: 'the push failed');

    final (desktop, desktopSync) = await install();
    expect(desktop.identity.clientName, isNot(phone.identity.clientName));
    final remote = await desktopSync.takeForeign();

    expect(remote, isNotNull);
    expect(remote!.songs.map((s) => s.id), songs.map((s) => s.id));
    expect(remote.currentIndex, 1);
    expect(remote.position, const Duration(milliseconds: 61234));
    expect(remote.changedBy, phone.identity.clientName);
  });
}
