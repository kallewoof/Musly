import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/models.dart';
import 'package:musly/providers/library_provider.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/library_database_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../bootstrap.dart';

/// A server whose library is [albums]; fetching an album in [failing] fails.
class _Server extends SubsonicService {
  Map<String, List<Song>> albums = {};
  Set<String> failing = {};

  @override
  bool get isConfigured => true;

  @override
  Future<List<Album>> getAlbumList(
          {String type = 'recent', int size = 20, int offset = 0}) async =>
      offset == 0
          ? [for (final id in albums.keys) Album(id: id, name: id)]
          : [];

  @override
  Future<List<Song>> getAlbumSongs(String albumId) async {
    if (failing.contains(albumId)) throw Exception('network down');
    return albums[albumId]!;
  }
}

/// How the library cache follows songs removed on the server.
void main() {
  initializeTestEnvironment();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  late _Server server;
  late LibraryProvider library;
  final cache = LibraryDatabaseService();

  Song song(String id, String album) => Song(id: id, title: id, albumId: album);

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('musly_prune_');
    await databaseFactory.setDatabasesPath(dir.path);
    server = _Server()
      ..albums = {
        'A': [song('a1', 'A'), song('a2', 'A')],
        'B': [song('b1', 'B')],
      };
    library = LibraryProvider(server, MuslyAudioHandler());
    await library.debugRefreshInBackground();
  });

  tearDown(() async {
    await cache.close();
    dir.deleteSync(recursive: true);
  });

  Future<Set<String>> cached() async =>
      {for (final s in await cache.getAllSongs()) s.id};

  // RD: the refresh only adds, so songs and albums removed from the server stay in the cache, and Smart Shuffle
  // (which picks from it) queues songs whose files are gone, which never play.
  test('a refresh drops the songs and albums the server no longer has',
      () async {
    server.albums = {
      'A': [song('a1', 'A')],
    };

    await library.debugRefreshInBackground();

    expect(await cached(), {'a1'});
    expect({for (final s in library.cachedAllSongs) s.id}, {'a1'});
    expect({for (final a in await cache.getAllAlbums()) a.id}, {'A'});
  });

  // RD: an album whose songs failed to load counts as emptied, so a network hiccup during the refresh wipes its
  // songs from the cache.
  test('a refresh that failed to load an album drops nothing', () async {
    server.albums = {
      'A': [song('a1', 'A')],
      'B': [song('b1', 'B')],
    };
    server.failing = {'B'};

    await library.debugRefreshInBackground();

    expect(await cached(), {'a1', 'a2', 'b1'});
  });

  // RD: the prune removes local files, which no server lists.
  test('local files stay', () async {
    await cache.insertSongsBatch([
      Song(id: '/music/x.mp3', title: 'x', isLocal: true, path: '/music/x.mp3')
    ]);
    server.albums = {
      'A': [song('a1', 'A')],
    };

    await library.debugRefreshInBackground();

    expect(await cached(), contains('/music/x.mp3'));
  });
}
