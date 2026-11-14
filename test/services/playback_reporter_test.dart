import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/song.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/jukebox_service.dart';
import 'package:musly/services/playback_reporter.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/services/transcoding_service.dart';
import 'package:musly/services/upnp_service.dart';

import '../bootstrap.dart';
import '../test_helpers.dart';

class _Player extends PlayerProvider {
  _Player()
      : super(
            SubsonicService(),
            StorageService(),
            FakeCastService(),
            UpnpService(),
            MuslyAudioHandler(),
            JukeboxService(),
            TranscodingService());

  Song? song;
  bool playing = false;
  Duration pos = Duration.zero;

  @override
  Song? get currentSong => song;
  @override
  bool get isPlaying => playing;
  @override
  Duration get position => pos;

  void show({Song? song, bool? playing, int? seconds, bool clearSong = false}) {
    if (song != null || clearSong) this.song = song;
    if (playing != null) this.playing = playing;
    if (seconds != null) pos = Duration(seconds: seconds);
    notifyListeners();
  }
}

class _Server extends SubsonicService {
  final reports = <String>[];
  Set<String> extensions = {'playbackReport'};

  @override
  bool get isConfigured => true;
  @override
  Future<Set<String>> openSubsonicExtensions() async => extensions;
  // A stop answers slowly, as over a real network, so reports sent side by side would land out of order.
  @override
  Future<void> reportPlayback(
      String id, String state, Duration position) async {
    if (state == 'stopped') {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    reports.add('$state $id ${position.inSeconds}');
  }
}

void main() {
  initializeTestEnvironment();

  final a = Song(id: 'a', title: 'A', duration: 200);
  final b = Song(id: 'b', title: 'B', duration: 180);
  late _Player player;
  late _Server server;

  setUp(() {
    player = _Player();
    server = _Server();
    PlaybackReporter(player, server).start();
  });

  tearDown(() => player.dispose());

  Future<void> settled() =>
      Future<void>.delayed(const Duration(milliseconds: 100));

  // RD: leaving a playing song is not reported, or the next song's start overtakes it, so the server never counts a skip.
  test(
      'reports a song left while playing as stopped, before the next one starts',
      () async {
    player.show(song: a, playing: true, seconds: 0);
    player.show(seconds: 30);
    player.show(song: b, seconds: 0);
    await settled();

    expect(server.reports, ['starting a 0', 'stopped a 30', 'starting b 0']);
  });

  // RD: a song swapped out while paused counts as skipped, so adopting another device's queue (or restoring one) records a skip the user never made.
  test('gives no verdict on a song replaced while paused', () async {
    player.show(song: a, playing: true, seconds: 0);
    player.show(seconds: 30);
    player.show(playing: false);
    player.show(song: b);
    await settled();

    expect(server.reports, ['starting a 0', 'paused a 30']);
  });

  // RD: the player goes idle between a finished song and the next one, so a song that ran to its end is never reported and never counts as finished.
  test(
      'reports a song that ran to its end even with the player idle in between',
      () async {
    player.show(song: a, playing: true, seconds: 0);
    player.show(seconds: 195);
    player.show(playing: false);
    player.show(song: b, playing: true, seconds: 0);
    await settled();

    expect(server.reports,
        ['starting a 0', 'paused a 195', 'stopped a 195', 'starting b 0']);
  });

  // RD: a restored, paused song is announced at launch, or its first play goes out as a resume the server cannot place.
  test('announces a restored song only when it starts playing', () async {
    player.show(song: a, playing: false, seconds: 40);
    await settled();
    expect(server.reports, isEmpty);

    player.show(playing: true);
    player.show(seconds: 50);
    player.show(playing: false);
    player.show(playing: true);
    await settled();

    expect(server.reports, ['starting a 40', 'paused a 50', 'playing a 50']);
  });

  // RD: a local file's id is not a server id, so reporting it makes the server reject the report or count another song.
  test('reports nothing for a local file', () async {
    final local =
        Song(id: '/music/x.mp3', title: 'X', duration: 100, isLocal: true);
    player.show(song: local, playing: true, seconds: 0);
    player.show(song: a, seconds: 0);
    await settled();

    expect(server.reports, ['starting a 0']);
  });

  // RD: a server without playbackReport is sent a request on every pause and song change, each one failing.
  test('reports nothing to a server without playback reports', () async {
    server.extensions = {};
    player.show(song: a, playing: true, seconds: 0);
    player.show(playing: false);
    await settled();

    expect(server.reports, isEmpty);
  });
}
