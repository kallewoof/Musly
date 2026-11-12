import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:musly/models/models.dart';
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

/// What the player does when playback stops making progress: a damaged file that leaves the decoder stuck
/// must not halt the queue.
void main() {
  initializeTestEnvironment();

  late FakeQueueServer server;
  late SubsonicService service;
  late PlayerProvider player;

  Song song(String id) => Song(id: id, title: 'T-$id', duration: 200);

  setUp(() async {
    server = FakeQueueServer();
    await server.start();
    SharedPreferences.setMockInitialValues({});
    await StorageService().init();
    service = SubsonicService();
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
      TranscodingService(),
    );
    player.queue.addAll([song('a'), song('b')]);
    await player.adoptTrackAt(0);
  });

  tearDown(() async {
    player.dispose();
    await server.stop();
  });

  /// Runs [ticks] checks, the way the one-second timer would. Moving on starts loading the next song,
  /// which has no audio backend in tests; the guarded zone absorbs that.
  Future<void> check(int ticks) async {
    runZonedGuarded(() {
      for (var i = 0; i < ticks; i++) {
        player.checkForStallAtEnd();
      }
    }, (_, __) {});
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  // RD: a damaged file leaves the decoder stuck at the song's end while still playing, so nothing ever moves
  // on and the queue halts there.
  test('a song stuck at its end moves on to the next', () async {
    await player.seek(const Duration(seconds: 199));
    player.debugSetPlaying(true);

    await check(4);

    expect(player.currentSong?.id, 'b');
  });

  // RD: moving on jumps to the next entry of the loaded gapless playlist, which the stuck decoder never
  // starts, so the queue halts on the next song at 0:00 instead. Tests have no decoder to get stuck, so
  // the jump would appear to work here: what is checked is that the stuck playlist is replaced.
  test('a stuck gapless queue loads the next song afresh', () async {
    final stuck = ConcatenatingAudioSource(children: []);
    player.debugGaplessSource = stuck;
    await player.seek(const Duration(seconds: 199));
    player.debugSetPlaying(true);

    await check(4);

    expect(player.currentSong?.id, 'b');
    expect(player.debugGaplessSource, isNot(same(stuck)));
  });

  // RD: the recovery ignores repeat-one and moves to the next song, so a song set to repeat plays once.
  test('with repeat-one a stuck song starts over', () async {
    player.setRepeatMode(RepeatMode.one);
    await player.seek(const Duration(seconds: 199));
    player.debugSetPlaying(true);

    await check(4);

    expect(player.currentSong?.id, 'a');
    expect(player.position, Duration.zero);
  });

  // RD: the watchdog takes any pause in progress for a stuck file, so a song buffering on a slow network is
  // skipped part-way through.
  test('a pause in progress mid-song is left alone', () async {
    await player.seek(const Duration(seconds: 60));
    player.debugSetPlaying(true);

    await check(10);

    expect(player.currentSong?.id, 'a');
  });

  // RD: a song paused in its last seconds counts as stuck, so it is skipped while the user is away.
  test('a song paused near its end is left alone', () async {
    await player.seek(const Duration(seconds: 199));

    await check(10);

    expect(player.currentSong?.id, 'a');
  });

  // RD: the check exists but is never scheduled, so outside tests nothing runs it and a stuck song stays
  // stuck.
  test('the check runs on its own once a second', () async {
    // Built inside a guarded zone: the timer's callback runs in the zone the timer was made in, and
    // moving on starts loading the next song, which has no audio backend in tests.
    late PlayerProvider timed;
    runZonedGuarded(() {
      timed = PlayerProvider(
        service,
        StorageService(),
        FakeCastService(),
        UpnpService(),
        MuslyAudioHandler(),
        JukeboxService(),
        TranscodingService(),
      );
    }, (_, __) {});
    timed.queue.addAll([song('a'), song('b')]);
    await timed.adoptTrackAt(0);
    await timed.seek(const Duration(seconds: 199));
    timed.debugSetPlaying(true);

    await Future<void>.delayed(const Duration(milliseconds: 4500));

    expect(timed.currentSong?.id, 'b');
    timed.dispose();
  });
}
