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

  group('stale and unsupported', () {
    // RD: a queue that cannot be pushed leaves the older pending change in place, which is sent later
    // although this device has moved on (cleared its queue, or plays a local file).
    test('an unpushable change discards the older pending one', () async {
      sync.markChanged([_song('a')], 0, const Duration(seconds: 5));
      sync.markChanged([], -1, Duration.zero);
      await sync.flush();

      expect(server.saves, isEmpty);
      expect(sync.hasUnsentChange, isFalse);
    });

    // RD: a laptop that paused offline overwrites, on reconnecting, the queue the phone saved since.
    test('a change that waited is dropped when another device saved after it',
        () async {
      server.failSaves = true;
      sync.markChanged([_song('mine')], 0, const Duration(seconds: 5));
      await sync.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      server.saveFromOtherDevice('Musly-ios-other', ['theirs'], 0, 1000);
      server.failSaves = false;

      await sync.flush();

      expect(server.saves, isEmpty);
      expect(sync.hasUnsentChange, isFalse);
      expect((await sync.takeForeign())!.songs.single.id, 'theirs');
    });

    // RD: the staleness check drops every change that waited once any other device has ever saved, so
    // progress made offline never reaches the server.
    test('a change that waited is still sent when the other save is older',
        () async {
      server.saveFromOtherDevice('Musly-ios-other', ['theirs'], 0, 1000);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      server.failSaves = true;
      sync.markChanged([_song('mine')], 0, const Duration(seconds: 5));
      await sync.flush();
      server.failSaves = false;

      await sync.flush();

      expect(server.saves.single['id'], ['mine']);
    });

    // RD: every push to a server without the index-based queue fails and stays pending, and each press of
    // play waits on a request that cannot succeed.
    test('a server without the index-based queue is left alone', () async {
      server.indexBasedQueue = false;
      final fresh = SubsonicService();
      await fresh.configure(ServerConfig(
          serverUrl: 'http://127.0.0.1:${server.port}',
          username: 'u',
          password: 'p'));
      sync = PlayQueueSync(fresh);
      server.saveFromOtherDevice('Musly-ios-other', ['theirs'], 0, 1000);
      final getsBefore = server.gets;

      sync.markChanged([_song('mine')], 0, const Duration(seconds: 5));
      await sync.flush();

      expect(server.saves, isEmpty);
      expect(await sync.takeForeign(), isNull);
      expect(server.gets, getsBefore);
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
