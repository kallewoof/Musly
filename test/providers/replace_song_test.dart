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

  group('the saved queue', () {
    late FakeQueueServer server;
    late PlayerProvider player;
    late Directory dir;

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
      dir = Directory.systemTemp.createTempSync('musly_queue_tags_');
      await databaseFactory.setDatabasesPath(dir.path);
    });

    tearDown(() async {
      player.dispose();
      await server.stop();
      await LibraryDatabaseService().close();
      dir.deleteSync(recursive: true);
    });

    Future<void> queue(List<Song> songs, int index) async {
      runZonedGuarded(
          () =>
              player.playSong(songs[index], playlist: songs, startIndex: index),
          (_, __) {});
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    // RD: the queue restored at launch keeps the copies it was saved with, so a song whose tags were fixed on the
    // server shows its old title and artist in Now Playing for as long as it stays queued.
    test('takes the tags the library loaded for the songs it holds', () async {
      await queue([Song(id: 's1', title: 'Song 1'), old], 1);
      final db = LibraryDatabaseService();
      await db.insertSongsBatch([Song(id: 's1', title: 'Song 1'), edited]);
      await db.insertAlbumsBatch([Album(id: 'al1', name: 'Album 1')]);
      final library = LibraryProvider(SubsonicService(), MuslyAudioHandler());
      player.setLibraryProvider(library);

      await library.ensureLibraryLoaded();

      expect(player.currentSong?.artist, 'Artist A');
      expect(player.queue.map((s) => s.title), ['Song 1', 'Song 2']);
    });

    // RD: the tags are compared on the title alone, so a song whose only fix was its artist (a soundtrack track
    // credited to its composer) or its album keeps the old one in the queue.
    test('takes a fix of the title, the artist or the album alone', () async {
      final q = [
        Song(id: 'a', title: 'Track 1', artist: 'Composer A', album: 'Album 1'),
        Song(
            id: 'b',
            title: 'Track 2',
            artist: Song.unknownArtist,
            album: 'Album 1'),
        Song(
            id: 'c',
            title: 'Track 3',
            artist: 'Composer A',
            album: Song.unknownAlbum),
      ];
      await queue(q, 0);
      final fixed = [
        Song(
            id: 'a',
            title: 'Track One',
            artist: 'Composer A',
            album: 'Album 1'),
        Song(id: 'b', title: 'Track 2', artist: 'Composer A', album: 'Album 1'),
        Song(id: 'c', title: 'Track 3', artist: 'Composer A', album: 'Album 1'),
      ];

      player.takeLibraryTags(fixed);

      expect(player.queue, [same(fixed[0]), same(fixed[1]), same(fixed[2])]);
    });

    // RD: only the shown tags are compared, so a song that gained ReplayGain values on the server keeps playing
    // in the queue with none, at the flat fallback gain, until it is queued again.
    test('takes new ReplayGain values for the songs it holds', () async {
      final q = [
        Song(id: 'a', title: 'Track 1'),
        Song(id: 'b', title: 'Track 2', replayGainTrackGain: -3),
      ];
      await queue(q, 0);
      final fixed = [
        Song(id: 'a', title: 'Track 1', replayGainTrackGain: -7.2),
        Song(
            id: 'b',
            title: 'Track 2',
            replayGainTrackGain: -3,
            replayGainTrackPeak: 0.9),
      ];

      player.takeLibraryTags(fixed);

      expect(player.queue, [same(fixed[0]), same(fixed[1])]);
      expect(player.currentSong?.replayGainTrackGain, -7.2);
    });

    // RD: copies the library does not know (or local files, which have no server copy) are replaced or dropped,
    // so a queue of local files loses its songs when the library loads.
    test('leaves songs the library does not hold, and local files', () async {
      final local = Song(id: 's3', title: 'My Recording', isLocal: true);
      final elsewhere = Song(id: 's4', title: 'Song 4');
      await queue([local, elsewhere, old], 2);

      player.takeLibraryTags([edited, Song(id: 's3', title: 'Server Title')]);

      expect(player.queue, [same(local), same(elsewhere), same(edited)]);
    });
  });
}
