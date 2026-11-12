import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// How the player drives play-queue sync: what it adopts, and what it pushes when.
void main() {
  initializeTestEnvironment();

  late FakeQueueServer server;
  late PlayerProvider player;

  Song song(String id) => Song(id: id, title: 'T-$id', duration: 200);

  Future<PlayerProvider> playerWith(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    await StorageService().init();
    final service = SubsonicService();
    await service.configure(ServerConfig(
        serverUrl: 'http://127.0.0.1:${server.port}',
        username: 'u',
        password: 'p'));
    final p = PlayerProvider(
      service,
      StorageService(),
      FakeCastService(),
      UpnpService(),
      MuslyAudioHandler(),
      JukeboxService(),
      TranscodingService(),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return p;
  }

  /// Lets an unawaited push reach the fake server.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 200));

  setUp(() async {
    server = FakeQueueServer();
    await server.start();
  });

  tearDown(() async {
    player.dispose();
    await server.stop();
  });

  // RD: adoption replaces the queue but keeps this device's position, so play resumes the phone's song
  // from wherever this device last stopped.
  test('adopting a remote queue lands on its song and position', () async {
    player = await playerWith({});
    server.saveFromOtherDevice('Musly-ios-other', ['a', 'b', 'c'], 1, 61000);

    expect(await player.adoptRemoteQueue(), isTrue);

    expect(player.queue.map((s) => s.id), ['a', 'b', 'c']);
    expect(player.currentSong?.id, 'b');
    expect(player.position, const Duration(seconds: 61));
  });

  // RD: play() resumes the local queue without asking the server, so pressing play on the desktop ignores
  // where the phone stopped.
  test('play adopts the remote queue before resuming', () async {
    player = await playerWith({});
    server.saveFromOtherDevice('Musly-ios-other', ['a', 'b'], 1, 30000);

    // There is no audio backend in tests: loading the track fails inside just_audio's own futures, which
    // the guarded zone absorbs. The adoption play() starts with completes before that.
    runZonedGuarded(() => unawaited(player.play()), (_, __) {});
    await settle();

    expect(player.currentSong?.id, 'b');
    expect(player.position, const Duration(seconds: 30));
  });

  // RD: going to the background saves the queue locally but never flushes it, so a phone pocketed right
  // after a seek keeps its stop position to itself.
  test('going to the background pushes the position after a seek', () async {
    player = await playerWith({});
    player.queue.addAll([song('a'), song('b')]);
    await player.adoptTrackAt(1);
    await player.seek(const Duration(seconds: 42));

    player.didChangeAppLifecycleState(AppLifecycleState.paused);
    await settle();

    expect(server.saves, isNotEmpty);
    final save = server.saves.last;
    expect(save['id'], ['a', 'b']);
    expect(save['currentIndex'], ['1']);
    expect(save['position'], ['42000']);
  });

  // RD: pause leaves the change for the periodic tick, and a desktop window never goes to the background,
  // so pausing on the desktop and picking up the phone resumes from up to 30 s earlier.
  test('pause pushes immediately', () async {
    player = await playerWith({});
    player.queue.addAll([song('a'), song('b')]);
    await player.adoptTrackAt(1);
    player.debugSetPlaying(true);

    runZonedGuarded(() => unawaited(player.pause()), (_, __) {});
    await settle();

    expect(server.saves, isNotEmpty);
    expect(server.saves.last['currentIndex'], ['1']);
  });

  // RD: after the server answers, adoption re-checks only whether music is playing, so a song the user
  // picked while it waited is replaced by the other device's queue.
  test('a song picked while the server is asked is not replaced', () async {
    player = await playerWith({});
    server.saveFromOtherDevice('Musly-ios-other', ['a', 'b'], 1, 30000);
    server.getDelay = const Duration(milliseconds: 300);

    final adopting = player.adoptRemoteQueue();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    runZonedGuarded(
        () =>
            unawaited(player.playSong(song('mine'), playlist: [song('mine')])),
        (_, __) {});

    expect(await adopting, isFalse);
    expect(player.currentSong?.id, 'mine');
  });

  // RD: tapping the paused current song resumes through play(), which adopts the other device's queue,
  // so the song the user explicitly picked is not the one that plays.
  test('tapping the paused current song does not adopt', () async {
    player = await playerWith({});
    player.queue.addAll([song('a'), song('b')]);
    await player.adoptTrackAt(1);
    // Sent first, so the other device's save below is the newer one and adoption is on the table.
    player.didChangeAppLifecycleState(AppLifecycleState.paused);
    await settle();
    server.saveFromOtherDevice('Musly-ios-other', ['x'], 0, 30000);

    runZonedGuarded(() => unawaited(player.playSong(song('b'))), (_, __) {});
    await settle();

    expect(player.currentSong?.id, 'b');
    expect(player.queue.map((s) => s.id), ['a', 'b']);
  });

  // RD: pause marks the queue whether or not anything played, so a media key on a device that only
  // restored its queue pushes that queue over the one the phone left.
  test('pausing a player that was not playing pushes nothing', () async {
    player = await playerWith({
      'persistent_queue': jsonEncode([song('old').toJson()]),
      'persistent_queue_index': 0,
      'persistent_queue_song_id': 'old',
      'persistent_queue_position_ms': 5000,
    });

    runZonedGuarded(() => unawaited(player.pause()), (_, __) {});
    await settle();

    expect(server.saves, isEmpty);
  });

  // RD: stop resets the position before the queue is marked, so another device resumes the track from
  // the start instead of where it stopped.
  test('stop pushes the position it stopped at', () async {
    player = await playerWith({});
    player.queue.addAll([song('a'), song('b')]);
    await player.adoptTrackAt(1);
    await player.seek(const Duration(seconds: 42));
    player.debugSetPlaying(true);

    runZonedGuarded(() => unawaited(player.stop()), (_, __) {});
    await settle();

    expect(server.saves, isNotEmpty);
    expect(server.saves.last['position'], ['42000']);
  });

  // RD: closing the desktop window quits without a lifecycle change, so the position played to is saved
  // nowhere and the next start, here or on another device, begins the song at 0:00.
  test('closing the app while playing saves and pushes the position', () async {
    player = await playerWith({});
    player.queue.addAll([song('a'), song('b')]);
    await player.adoptTrackAt(1);
    await player.seek(const Duration(seconds: 42));
    player.debugSetPlaying(true);

    expect(await player.didRequestAppExit(), AppExitResponse.exit);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('persistent_queue_position_ms'), 42000);
    expect(prefs.getString('persistent_queue_song_id'), 'b');
    expect(server.saves, isNotEmpty);
    expect(server.saves.last['position'], ['42000']);
  });

  // RD: the exit handler marks whatever queue is loaded, so closing a device that only restored its queue
  // pushes it over the one the phone left.
  test('closing the app without playing pushes nothing', () async {
    player = await playerWith({
      'persistent_queue': jsonEncode([song('old').toJson()]),
      'persistent_queue_index': 0,
      'persistent_queue_song_id': 'old',
      'persistent_queue_position_ms': 5000,
    });

    expect(await player.didRequestAppExit(), AppExitResponse.exit);

    expect(server.saves, isEmpty);
  });

  List<dynamic> savedQueue(SharedPreferences prefs) =>
      jsonDecode(prefs.getString('persistent_queue')!) as List<dynamic>;

  // RD: the star changes only the in-memory current song, so the queue restored at the next start shows it
  // unstarred although the server has the star.
  test('a star on the playing song is in the saved queue', () async {
    player = await playerWith({});
    player.queue.addAll([song('a'), song('b')]);
    await player.adoptTrackAt(1);
    // The track change's own debounced save lands first, so only the star's save can carry the star.
    await Future<void>.delayed(const Duration(milliseconds: 400));

    await player.toggleFavorite();
    await settle();

    expect(player.queue[1].starred, isTrue);
    final saved = savedQueue(await SharedPreferences.getInstance());
    expect((saved[1] as Map)['id'], 'b');
    expect((saved[1] as Map)['starred'], isTrue);
  });

  // RD: starring a song from a list updates only the now-playing song, so the same song further down the
  // queue, and the next restart, show it unstarred.
  test('a star from a list reaches every queue copy of the song', () async {
    player = await playerWith({});
    player.queue.addAll([song('a'), song('b'), song('a')]);
    await player.adoptTrackAt(1);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    await player.toggleFavoriteForSong(song('a'));
    await settle();

    expect(player.queue.where((s) => s.id == 'a').map((s) => s.starred),
        [true, true]);
    final saved = savedQueue(await SharedPreferences.getInstance());
    expect((saved[0] as Map)['starred'], isTrue);
  });

  // RD: the star is saved by marking the queue changed, so starring on a device that only restored its queue
  // pushes that queue over the one the phone left.
  test('a star does not push the queue', () async {
    player = await playerWith({
      'persistent_queue': jsonEncode([song('old').toJson()]),
      'persistent_queue_index': 0,
      'persistent_queue_song_id': 'old',
      'persistent_queue_position_ms': 5000,
    });

    await player.toggleFavorite();
    player.didChangeAppLifecycleState(AppLifecycleState.paused);
    await settle();

    expect(player.currentSong?.starred, isTrue);
    expect(server.saves, isEmpty);
  });

  // RD: the idle player's position report of 0 at startup overwrites the restored position, so the app
  // reopens on the right song at 0:00 and play starts the song over.
  test('the restored position survives startup', () async {
    player = await playerWith({
      'persistent_queue': jsonEncode([song('a').toJson(), song('b').toJson()]),
      'persistent_queue_index': 1,
      'persistent_queue_song_id': 'b',
      'persistent_queue_position_ms': 26000,
    });
    await settle();

    expect(player.currentSong?.id, 'b');
    expect(player.position, const Duration(seconds: 26));
  });

  // RD: the lifecycle handler marks the queue restored at launch as changed, so a device opened but never
  // played overwrites the queue the phone left on the server.
  test('a queue that was only restored is never pushed', () async {
    player = await playerWith({
      'persistent_queue': jsonEncode([song('old').toJson()]),
      'persistent_queue_index': 0,
      'persistent_queue_song_id': 'old',
      'persistent_queue_position_ms': 5000,
    });
    expect(player.currentSong?.id, 'old');

    player.didChangeAppLifecycleState(AppLifecycleState.paused);
    player.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await settle();

    expect(server.saves, isEmpty);
  });
}
