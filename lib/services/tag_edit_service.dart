import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import 'subsonic_service.dart';

/// The text of a song's four editable tags, as the edit sheet shows them.
typedef TagFields = ({
  String title,
  String artist,
  String composer,
  String album
});

/// Edits a song's tags through the server's tag overlay (navidrome's `unimouseTagOverlay`): the files stay as
/// they are, and the server shows the song with the edit once it has re-read it, which takes a few seconds.
class TagEditService {
  TagEditService(
    this._subsonic,
    this._library,
    this._player, {
    this.poll = const Duration(seconds: 1),
    this.tries = 15,
  });

  final SubsonicService _subsonic;
  final LibraryProvider _library;
  final PlayerProvider _player;

  /// How often, and how many times, to look for the re-read song after an edit.
  final Duration poll;
  final int tries;

  /// What the sheet opens with: the song's tags as the server has them now, any edit included, and whether the
  /// song has an edit. The placeholders of missing tags show as empty.
  Future<({TagFields fields, bool edited})> load(String id) async {
    final overlay = await _subsonic.getTagOverlay(id);
    final now = await _subsonic.getSongWithComposers(id);
    return (
      fields: _fieldsOf(now.song, now.composers),
      edited: overlay.hasEdit
    );
  }

  /// Sends the fields of [edited] that differ from [initial] (an emptied one clears its tag), and puts the song
  /// with the edit in the library and the queue once the server shows it. Returns that song, or null when the
  /// server had not re-read it within the wait; the edit is saved either way.
  Future<Song?> save(String id, TagFields initial, TagFields edited) async {
    String? changed(String Function(TagFields f) field) =>
        field(edited).trim() == field(initial).trim()
            ? null
            : field(edited).trim();
    final title = changed((f) => f.title);
    final artist = changed((f) => f.artist);
    final composer = changed((f) => f.composer);
    final album = changed((f) => f.album);
    if (title == null && artist == null && composer == null && album == null) {
      throw ArgumentError('nothing changed');
    }
    await _subsonic.setTagOverlay(id,
        title: title, artist: artist, composer: composer, album: album);
    return _refresh(
        id,
        (f) =>
            (title == null || f.title == title) &&
            (artist == null || f.artist == artist) &&
            (composer == null || f.composer == composer) &&
            (album == null || f.album == album));
  }

  /// Drops the song's edit, and puts the song as its file has it in the library and the queue once the server
  /// shows a change from [before]. Returns that song, or null when nothing changed within the wait.
  Future<Song?> reset(String id, TagFields before) async {
    await _subsonic.resetTagOverlay(id);
    return _refresh(id, (f) => f != before);
  }

  Future<Song?> _refresh(String id, bool Function(TagFields f) shows) async {
    for (var i = 0; i < tries; i++) {
      await Future<void>.delayed(poll);
      final now = await _subsonic.getSongWithComposers(id);
      if (shows(_fieldsOf(now.song, now.composers))) {
        await _library.replaceSong(now.song);
        _player.replaceSong(now.song);
        return now.song;
      }
    }
    return null;
  }

  static TagFields _fieldsOf(Song song, List<String> composers) => (
        title: song.title,
        artist: song.knownArtist ?? '',
        composer: composers.join(', '),
        album: song.album == Song.unknownAlbum ? '' : song.album ?? '',
      );
}
