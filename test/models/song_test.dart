import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/song.dart';

void main() {
  group('Song', () {
    test('should create a Song from JSON', () {
      final json = {
        'id': '123',
        'title': 'Test Song',
        'album': 'Test Album',
        'artist': 'Test Artist',
        'duration': 180,
        'track': 5,
      };

      final song = Song.fromJson(json);

      expect(song.id, '123');
      expect(song.title, 'Test Song');
      expect(song.album, 'Test Album');
      expect(song.artist, 'Test Artist');
      expect(song.duration, 180);
      expect(song.track, 5);
    });

    test('should handle missing fields in JSON', () {
      final json = {'id': '123', 'title': 'Test Song'};

      final song = Song.fromJson(json);

      expect(song.id, '123');
      expect(song.title, 'Test Song');
      expect(song.album, isNull);
      expect(song.artist, isNull);
      expect(song.duration, isNull);
      expect(song.created, isNull);
    });

    test('should parse created field from JSON', () {
      final json = {
        'id': '123',
        'title': 'Test Song',
        'created': '2026-03-18T13:37:27.257653751Z',
      };

      final song = Song.fromJson(json);

      expect(song.created, isNotNull);
      expect(song.created!.year, 2026);
      expect(song.created!.month, 3);
      expect(song.created!.day, 18);
    });

    test('should convert Song to JSON', () {
      final song = Song(
        id: '123',
        title: 'Test Song',
        album: 'Test Album',
        artist: 'Test Artist',
        duration: 180,
        track: 5,
      );

      final json = song.toJson();

      expect(json['id'], '123');
      expect(json['title'], 'Test Song');
      expect(json['album'], 'Test Album');
      expect(json['artist'], 'Test Artist');
      expect(json['duration'], 180);
      expect(json['track'], 5);
    });

    test('should parse replayGain values from nested map with numbers or strings', () {
      final json = {
        'id': '123',
        'title': 'Test Song',
        'replayGain': {
          'trackGain': -7.2,
          'albumGain': '-6.5 dB',
          'trackPeak': '0.985000',
          'albumPeak': 1.0,
        },
      };

      final song = Song.fromJson(json);

      expect(song.replayGainTrackGain, -7.2);
      expect(song.replayGainAlbumGain, -6.5);
      expect(song.replayGainTrackPeak, 0.985);
      expect(song.replayGainAlbumPeak, 1.0);
    });

    test('should parse replayGain values from flat fallback keys', () {
      final json = {
        'id': '123',
        'title': 'Test Song',
        'replayGainTrackGain': '-8.1 dB',
        'albumGain': -5.4,
        'rgTrackPeak': 0.95,
      };

      final song = Song.fromJson(json);

      expect(song.replayGainTrackGain, -8.1);
      expect(song.replayGainAlbumGain, -5.4);
      expect(song.replayGainTrackPeak, 0.95);
    });

    // RD: toJson leaves the star out, so every song read back from a saved queue or cache shows unstarred
    // although the server has it starred.
    test('keeps its star through toJson and fromJson', () {
      final song = Song(id: '1', title: 'T', starred: true);

      expect(Song.fromJson(song.toJson()).starred, isTrue);
    });

    // RD: toJson writes the flag for unstarred songs too, and fromJson, reading any value as the server's
    // timestamp, brings every unstarred song back starred.
    test('stays unstarred through toJson and fromJson', () {
      final song = Song(id: '1', title: 'T', starred: false);

      expect(Song.fromJson(song.toJson()).starred, isFalse);
    });
  });
}