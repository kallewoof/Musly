import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/models.dart';
import 'package:musly/providers/library_provider.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/jukebox_service.dart';
import 'package:musly/services/library_database_service.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/services/transcoding_service.dart';
import 'package:musly/services/upnp_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../bootstrap.dart';
import '../fake_queue_server.dart';
import '../test_helpers.dart';

/// A song whose tags were edited on the server replaces the copies the app holds.
void main() {
  initializeTestEnvironment();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final old = Song(id: 's2', title: 'song_2', artist: Song.unknownArtist);
  final edited = Song(id: 's2', title: 'Song 2', artist: 'Artist A');

  group('the player', () {
    late FakeQueueServer server;
    late PlayerProvider player;
    late MuslyAudioHandler handler;

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
      handler = MuslyAudioHandler();
      player = PlayerProvider(service, StorageService(), FakeCastService(),
          UpnpService(), handler, JukeboxService(), TranscodingService());
    });

    tearDown(() async {
      player.dispose();
      await server.stop();
    });

    // RD: only the queue's copies are replaced, so Now Playing and the lock screen keep the old title of the song
    // that is playing until the next track.
    test(
        'replaces the playing song, its queue copies and the lock screen details',
        () async {
      final queue = [
        Song(id: 's1', title: 'Song 1'),
        old,
        Song(id: 's3', title: 'Song 3')
      ];
      runZonedGuarded(
          () => player.playSong(old, playlist: queue, startIndex: 1),
          (_, __) {});
      await Future<void>.delayed(const Duration(milliseconds: 200));

      player.replaceSong(edited);

      expect(player.currentSong, same(edited));
      expect(player.queue.map((s) => s.title), ['Song 1', 'Song 2', 'Song 3']);
      expect(handler.mediaItem.value?.title, 'Song 2');
      expect(handler.mediaItem.value?.artist, 'Artist A');
    });
  });

  group('the library', () {
    late Directory dir;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('musly_replace_');
      await databaseFactory.setDatabasesPath(dir.path);
    });

    tearDown(() async {
      await LibraryDatabaseService().close();
      dir.deleteSync(recursive: true);
    });

    // RD: the cached library keeps the old copy (or only memory is updated), so search and the mixes show the old
    // tags, and the next launch loads them back from the database.
    test('replaces the cached song in memory and in the library database',
        () async {
      final db = LibraryDatabaseService();
      await db.insertSongsBatch([Song(id: 's1', title: 'Song 1'), old]);
      await db.insertAlbumsBatch([Album(id: 'al1', name: 'Album 1')]);
      final library = LibraryProvider(SubsonicService(), MuslyAudioHandler());
      await library.ensureLibraryLoaded();
      expect(
          library.cachedAllSongs.map((s) => s.title), containsAll(['song_2']));

      await library.replaceSong(edited);

      expect(library.cachedAllSongs.map((s) => s.title).toSet(),
          {'Song 1', 'Song 2'});
      expect((await db.getSong('s2'))?.title, 'Song 2');
    });
  });
}
