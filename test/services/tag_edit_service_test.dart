import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/song.dart';
import 'package:musly/models/tag_overlay.dart';
import 'package:musly/providers/library_provider.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/jukebox_service.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/services/tag_edit_service.dart';
import 'package:musly/services/transcoding_service.dart';
import 'package:musly/services/upnp_service.dart';

import '../bootstrap.dart';
import '../test_helpers.dart';

/// The server: the song it returns from getSong in turn (the last one repeats), and the edits it was sent.
class _Server extends SubsonicService {
  _Server(this.songs, {this.composers = const []});

  final List<Song> songs;
  final List<String> composers;
  TagOverlay overlay = const TagOverlay(id: 's1');
  final sent = <Map<String, String?>>[];
  int resets = 0;
  int _reads = 0;

  @override
  Future<TagOverlay> getTagOverlay(String id) async => overlay;

  @override
  Future<TagOverlay> setTagOverlay(String id,
      {String? title, String? artist, String? composer, String? album}) async {
    sent.add({
      'title': title,
      'artist': artist,
      'composer': composer,
      'album': album
    });
    return overlay;
  }

  @override
  Future<void> resetTagOverlay(String id) async => resets++;

  @override
  Future<({Song song, List<String> composers})> getSongWithComposers(
      String id) async {
    final song = songs[_reads < songs.length ? _reads : songs.length - 1];
    _reads++;
    return (song: song, composers: composers);
  }
}

class _Library extends LibraryProvider {
  _Library(SubsonicService s) : super(s, MuslyAudioHandler());
  final replaced = <Song>[];
  @override
  Future<void> replaceSong(Song song) async => replaced.add(song);
}

class _Player extends PlayerProvider {
  _Player(SubsonicService s)
      : super(s, StorageService(), FakeCastService(), UpnpService(),
            MuslyAudioHandler(), JukeboxService(), TranscodingService());
  final replaced = <Song>[];
  @override
  void replaceSong(Song song) => replaced.add(song);
}

void main() {
  initializeTestEnvironment();

  final file = Song(
      id: 's1',
      title: 'song_1',
      artist: Song.unknownArtist,
      album: Song.unknownAlbum);
  final edited = Song(
      id: 's1',
      title: 'Song 1',
      artist: 'Producer A feat. Voice A',
      album: Song.unknownAlbum);
  const fromFile = (title: 'song_1', artist: '', composer: '', album: '');

  late _Library library;
  late _Player player;

  TagEditService service(_Server server) {
    library = _Library(server);
    player = _Player(server);
    return TagEditService(server, library, player,
        poll: Duration.zero, tries: 3);
  }

  // RD: the editor shows Navidrome's placeholders as values, so saving untouched fields writes "[Unknown Artist]"
  // into the edit; or the composers (not part of Song) are left out, so the field opens empty and an edit of
  // another field never shows a song's composer.
  test(
      'opens with the song as the server has it, placeholders as empty, composers joined',
      () async {
    final server = _Server([file], composers: ['Composer A', 'Composer B'])
      ..overlay = const TagOverlay(id: 's1', title: 'song_1');

    final loaded = await service(server).load('s1');

    expect(loaded.fields, (
      title: 'song_1',
      artist: '',
      composer: 'Composer A, Composer B',
      album: ''
    ));
    expect(loaded.edited, isTrue);
  });

  // RD: every field is sent, so the edit pins the file's own values too and a later fix of the file is hidden
  // behind them; or an emptied field is skipped and a wrong tag can never be cleared.
  test('sends only the changed fields, trimmed, and an emptied one as empty',
      () async {
    final server = _Server([edited]);

    await service(server).save('s1', (
      title: 'song_1',
      artist: '',
      composer: 'Wrong',
      album: ''
    ), (
      title: ' Song 1 ',
      artist: 'Producer A feat. Voice A',
      composer: '',
      album: ''
    ));

    expect(server.sent, [
      {
        'title': 'Song 1',
        'artist': 'Producer A feat. Voice A',
        'composer': '',
        'album': null
      }
    ]);
  });

  // RD: the library and queue take the server's song before it has re-read the file, so the old title replaces
  // the new one; or they never take it, so the edit shows only after the next full library sync.
  test('puts the song in the library and queue once the server shows the edit',
      () async {
    final server = _Server([file, file, edited]);

    final song = await service(server).save('s1', fromFile, (
      title: 'Song 1',
      artist: 'Producer A feat. Voice A',
      composer: '',
      album: ''
    ));

    expect(song, same(edited));
    expect(library.replaced, [edited]);
    expect(player.replaced, [edited]);
  });

  // RD: a server that has not re-read the song in time is reported as done, and the sheet says "saved" while the
  // library keeps showing the old tags.
  test('reports no song when the server has not re-read it in time', () async {
    final server = _Server([file]);

    final song = await service(server).save(
        's1', fromFile, (title: 'Song 1', artist: '', composer: '', album: ''));

    expect(song, isNull);
    expect(library.replaced, isEmpty);
    expect(player.replaced, isEmpty);
  });

  // RD: a revert drops the edit on the server but the library keeps the edited copy until the next sync.
  test('reverts on the server, then takes the song as its file has it',
      () async {
    final server = _Server([edited, file]);
    const shown = (
      title: 'Song 1',
      artist: 'Producer A feat. Voice A',
      composer: '',
      album: ''
    );

    final song = await service(server).reset('s1', shown);

    expect(server.resets, 1);
    expect(song, same(file));
    expect(library.replaced, [file]);
  });
}
