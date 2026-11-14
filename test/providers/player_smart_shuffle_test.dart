import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/models.dart';
import 'package:musly/providers/library_provider.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/jukebox_service.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/services/transcoding_service.dart';
import 'package:musly/services/upnp_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bootstrap.dart';
import '../fake_queue_server.dart';
import '../test_helpers.dart';

class _Library extends LibraryProvider {
  _Library(SubsonicService s, this.songs) : super(s, MuslyAudioHandler());

  final List<Song> songs;

  @override
  List<Song> get cachedAllSongs => songs;
}

/// Smart Shuffle and the song radio in the player: what starts them, what keeps them going, what ends them.
void main() {
  initializeTestEnvironment();

  late FakeQueueServer server;
  late PlayerProvider player;
  late _Library library;

  setUp(() async {
    server = FakeQueueServer();
    await server.start();
    SharedPreferences.setMockInitialValues({});
    await StorageService().init();
    final service = SubsonicService();
    await service.configure(ServerConfig(
        serverUrl: 'http://127.0.0.1:${server.port}',
        username: 'u',
        password: 'p'));
    player = PlayerProvider(
        service,
        StorageService(),
        FakeCastService(),
        UpnpService(),
        MuslyAudioHandler(),
        JukeboxService(),
        TranscodingService());
    library = _Library(service, [
      for (var i = 0; i < 30; i++)
        Song(id: 's$i', title: 'T$i', artist: 'A${i % 6}', duration: 200),
    ]);
    player.setLibraryProvider(library);
  });

  tearDown(() async {
    player.dispose();
    await server.stop();
  });

  /// Runs [action], which loads audio that tests cannot play: the guarded zone absorbs that, and the queue
  /// and mode are in place before the load.
  Future<void> start(FutureOr<void> Function() action) async {
    runZonedGuarded(() => action(), (_, __) {});
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  Set<String> ids() => player.queue.map((s) => s.id).toSet();

  // RD: the button plays a plain random shuffle, or nothing, instead of a queue that keeps itself going.
  test('Smart Shuffle starts a queue of picks from the library', () async {
    await start(player.smartShuffle);

    expect(player.isSmartShuffle, isTrue);
    expect(player.queue, hasLength(10));
    expect(ids(), hasLength(10));
  });

  // RD: a Smart Shuffle queue is topped up from the song radio, or not at all, so it ends after its first ten songs.
  test('tops up a Smart Shuffle queue with new picks as it runs low', () async {
    await start(player.smartShuffle);
    await start(() => player.adoptTrackAt(8));
    final first = ids();

    await start(player.skipNext);

    expect(player.queue, hasLength(20));
    expect(ids(), hasLength(20), reason: 'no song queued twice');
    expect(ids().containsAll(first), isTrue);
  });

  // RD: a skip within the queue counts as starting a new one, so the first skip ends Smart Shuffle.
  test('a skip keeps Smart Shuffle going', () async {
    await start(player.smartShuffle);
    // Without the gapless source a skip replays the queue through playSong, the path that could end it.
    player.debugGaplessSource = null;
    await start(() => player.skipToIndex(3));

    expect(player.isSmartShuffle, isTrue);
  });

  // RD: once a radio or Smart Shuffle has run, every later queue (an album, a playlist) is topped up by it when it ends.
  test('playing another queue ends Smart Shuffle and the song radio', () async {
    final album = library.songs.take(3).toList();

    await start(player.smartShuffle);
    await start(() => player.playSong(album.last, playlist: album));
    expect(player.isSmartShuffle, isFalse);

    await start(() => player.playSongWithRadio(library.songs[20]));
    expect(player.isRadioQueue, isTrue);
    await start(() => player.playSong(album.first, playlist: album));
    expect(player.isRadioQueue, isFalse);
  });
}
