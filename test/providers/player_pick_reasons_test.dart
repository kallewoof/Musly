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

/// Why the current song was picked: which queues carry reasons, and which replace or keep them.
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

  /// Runs [action], which loads audio that tests cannot play: the guarded zone absorbs that.
  Future<void> start(FutureOr<void> Function() action) async {
    runZonedGuarded(() => action(), (_, __) {});
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  // RD: the top-ups are queued without their draws, so "why?" disappears after the first ten Smart Shuffle songs.
  test('explains Smart Shuffle picks, the top-ups included', () async {
    await start(player.smartShuffle);
    expect(player.currentPickReason, isA<ShufflePick>());

    await start(() => player.adoptTrackAt(8));
    await start(player.skipNext);
    await start(() => player.adoptTrackAt(15));

    expect(player.queue, hasLength(20));
    expect(player.currentPickReason, isA<ShufflePick>());
  });

  // RD: a new queue keeps the reasons of the one it replaced, so a song from an album shows why a mix picked it.
  test(
      'a queue started without reasons shows none, and one with them shows them',
      () async {
    final album = library.songs.take(3).toList();
    await start(player.smartShuffle);

    await start(() => player.playSong(album.first, playlist: album));
    expect(player.currentPickReason, isNull);

    await start(() => player.playSong(album.first,
        playlist: album, reasons: {album.first.id: const ListenAgainPick()}));
    expect(player.currentPickReason, isA<ListenAgainPick>());
  });

  // RD: a skip within the queue counts as a new queue, so the reasons go after the first skip.
  test('a skip within the queue keeps its reasons', () async {
    await start(player.smartShuffle);
    player.debugGaplessSource = null;

    await start(() => player.skipToIndex(3));

    expect(player.currentPickReason, isA<ShufflePick>());
  });

  /// A radio queue of [seed] alone, run to its end so the radio tops it up, then on its first added song.
  /// (playSongWithRadio's own first fetch never runs here: its playSong fails on the audio load first.)
  Future<void> runRadioFrom(Song seed) async {
    await start(() => player.playSong(seed, playlist: [seed]));
    player.debugRefill = QueueRefill.radio;
    await start(player.skipNext);
    await start(() => player.adoptTrackAt(1));
  }

  // RD: radio songs are all labelled "similar", also when the server had none and the radio fell back to random songs.
  test('says where a radio song came from: similar songs or a fallback',
      () async {
    final seed = library.songs[20];
    server.similarIds = ['x1', 'x2'];
    await runRadioFrom(seed);
    expect(player.currentSong?.id, 'x1');
    var radio = player.currentPickReason as RadioPick;
    expect((radio.seedTitle, radio.source), (seed.title, RadioSource.similar));

    server.similarIds = const [];
    server.randomIds = ['r1'];
    await runRadioFrom(seed);
    expect(player.currentSong?.id, 'r1');
    radio = player.currentPickReason as RadioPick;
    expect(radio.source, RadioSource.random);
  });
}
