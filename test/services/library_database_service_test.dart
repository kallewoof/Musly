import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/song.dart';
import 'package:musly/services/library_database_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../bootstrap.dart';

/// The songs table as version 3 of the cache wrote it, before the per-user counts.
const _v3Songs = '''
  CREATE TABLE songs (
    id TEXT PRIMARY KEY, title TEXT NOT NULL, album TEXT, albumId TEXT, artist TEXT, artistId TEXT,
    track INTEGER, year INTEGER, genre TEXT, coverArt TEXT, duration INTEGER, bitRate INTEGER,
    suffix TEXT, contentType TEXT, size INTEGER, path TEXT, isLocal INTEGER DEFAULT 0,
    replayGainTrackGain REAL, replayGainAlbumGain REAL, replayGainTrackPeak REAL,
    replayGainAlbumPeak REAL, artistParticipants TEXT, created TEXT, starred INTEGER DEFAULT 0,
    userRating INTEGER
  )
''';

void main() {
  initializeTestEnvironment();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  late LibraryDatabaseService cache;
  final song =
      Song(id: 's1', title: 'T', playCount: 7, skipCount: 2, completeCount: 5);

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('musly_cache_');
    await databaseFactory.setDatabasesPath(dir.path);
    cache = LibraryDatabaseService();
  });

  tearDown(() async {
    await cache.close();
    dir.deleteSync(recursive: true);
  });

  // RD: the library cache drops the counts, so the mixes, which are scored from the cache, never see them.
  test('keeps each song\'s play, skip and completion counts', () async {
    await cache.insertSongsBatch([song]);
    final stored = (await cache.getAllSongs()).single;

    expect(
        [stored.playCount, stored.skipCount, stored.completeCount], [7, 2, 5]);
  });

  // RD: an existing install's cache never gains the new columns, so saving the library fails and it shows empty.
  test('upgrades a version 3 cache to hold the counts', () async {
    final old = await databaseFactory.openDatabase(
      p.join(dir.path, 'musly_library.db'),
      options: OpenDatabaseOptions(
          version: 3, onCreate: (db, _) => db.execute(_v3Songs)),
    );
    await old.close();

    await cache.insertSongsBatch([song]);
    final stored = (await cache.getAllSongs()).single;

    expect(
        [stored.playCount, stored.skipCount, stored.completeCount], [7, 2, 5]);
  });
}
