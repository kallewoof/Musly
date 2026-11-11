import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musly/models/models.dart';
import 'package:musly/services/play_queue_sync.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';

import '../fake_queue_server.dart';

Song _song(String id, {bool local = false}) => Song(
    id: id,
    title: 'T-$id',
    isLocal: local,
    path: local ? '/tmp/$id.mp3' : null);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeQueueServer server;
  late SubsonicService service;
  late PlayQueueSync sync;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().init();
    server = FakeQueueServer();
    await server.start();
    service = SubsonicService();
    await service.configure(ServerConfig(
        serverUrl: 'http://127.0.0.1:${server.port}',
        username: 'u',
        password: 'p'));
    sync = PlayQueueSync(service);
  });

  tearDown(() async {
    await server.stop();
  });

  group('push', () {
    // RD: local files are dropped from the pushed list but the index is not remapped, so the other device
    // resumes on the song after the one that was playing.
    test('drops local files and keeps the index on the current song', () async {
      sync.markChanged(
          [_song('a'), _song('x', local: true), _song('b'), _song('c')],
          2,
          const Duration(seconds: 61));
      await sync.flush();

      expect(server.saves, hasLength(1));
      final save = server.saves.single;
      expect(save['id'], ['a', 'b', 'c']);
      expect(save['currentIndex'], ['1']);
      expect(save['position'], ['61000']);
      expect(save['c'], [service.identity.clientName]);
    });

    // RD: an empty queue is pushed as a change, so clearing the queue on one device, or a fresh install,
    // wipes the stop position the phone left.
    test('never sends an empty queue', () async {
      sync.markChanged([], -1, Duration.zero);
      await sync.flush();

      expect(server.saves, isEmpty);
    });

    // RD: a push that fails while offline is dropped, so the stop position never reaches the server once
    // the connection is back.
    test('keeps a failed push pending and sends it on the next flush',
        () async {
      server.failSaves = true;
      sync.markChanged([_song('a')], 0, const Duration(seconds: 5));
      await sync.flush();
      expect(server.saves, isEmpty);
      expect(sync.hasUnsentChange, isTrue);

      server.failSaves = false;
      await sync.flush();

      expect(server.saves, hasLength(1));
      expect(sync.hasUnsentChange, isFalse);
    });
  });

  group('takeForeign', () {
    // RD: the remote queue is parsed with the wrong index or position, so the device resumes on another
    // song or from the start instead of where the phone stopped.
    test('offers the queue another device saved, at its song and position',
        () async {
      server.saveFromOtherDevice('Musly-ios-other', ['a', 'b', 'c'], 1, 61234);

      final remote = await sync.takeForeign();

      expect(remote, isNotNull);
      expect(remote!.songs.map((s) => s.id), ['a', 'b', 'c']);
      expect(remote.currentIndex, 1);
      expect(remote.position, const Duration(milliseconds: 61234));
    });

    // RD: changedBy is compared with the wrong name, so this device adopts its own earlier save on every
    // play and rewinds to its last push.
    test('ignores this install\'s own save', () async {
      sync.markChanged(
          [_song('a'), _song('b')], 1, const Duration(seconds: 30));
      await sync.flush();

      expect(server.queue!['changedBy'], service.identity.clientName);
      expect(await sync.takeForeign(), isNull);
    });

    // RD: the adoption is never recorded, so every press of play rewinds to where the other device stopped
    // hours ago.
    test('does not offer a save again once adopted, but offers a newer one',
        () async {
      server.saveFromOtherDevice('Musly-ios-other', ['a'], 0, 1000);
      final first = await sync.takeForeign();
      await sync.adopted(first!);

      expect(await sync.takeForeign(), isNull);

      server.saveFromOtherDevice('Musly-ios-other', ['b'], 0, 2000);
      final second = await sync.takeForeign();
      expect(second!.songs.single.id, 'b');
    });

    // RD: a device with progress the server has not seen yet adopts the older remote queue on reconnect,
    // and its own listening is lost.
    test('pushes an unsent local change instead of adopting', () async {
      server.saveFromOtherDevice('Musly-ios-other', ['a'], 0, 1000);
      sync.markChanged([_song('z')], 0, const Duration(seconds: 9));

      expect(await sync.takeForeign(), isNull);
      expect(server.saves.single['id'], ['z']);
    });

    // RD: an empty server queue is read as a queue at index 0, and the device crashes or clears its own.
    test('offers nothing when the server queue is empty', () async {
      expect(await sync.takeForeign(), isNull);
    });
  });
}
