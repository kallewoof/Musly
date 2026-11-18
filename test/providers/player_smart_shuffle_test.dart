import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/models.dart';
import 'package:musly/providers/library_provider.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/jukebox_service.dart';
import 'package:musly/services/recommendation_service.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/services/transcoding_service.dart';
import 'package:musly/services/upnp_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bootstrap.dart';
import '../fake_queue_server.dart';
import '../test_helpers.dart';

class _Library extends LibraryProvider {
  _Library(SubsonicService s, this.songs) : super(s, MuslyAudioHandler());

  final List<Song> songs;

  @override
  List<Song> get cachedAllSongs => songs;
}

/// Smart Shuffle and the song radio in the player: what starts them, what keeps them going, what ends them.
void main() {
  initializeTestEnvironment();

  late FakeQueueServer server;
  late PlayerProvider player;
  late _Library library;

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
    library = _Library(service, [
      for (var i = 0; i < 30; i++)
        Song(id: 's$i', title: 'T$i', artist: 'A${i % 6}', duration: 200),
    ]);
    player.setLibraryProvider(library);
  });

  tearDown(() async {
    player.dispose();
    await server.stop();
  });

  /// Runs [action], which loads audio that tests cannot play: the guarded zone absorbs that, and the queue
  /// and mode are in place before the load.
  Future<void> start(FutureOr<void> Function() action) async {
    runZonedGuarded(() => action(), (_, __) {});
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  Set<String> ids() => player.queue.map((s) => s.id).toSet();

  // RD: the button plays a plain random shuffle, or nothing, instead of a queue that keeps itself going.
  test('Smart Shuffle starts a queue of picks from the library', () async {
    await start(player.smartShuffle);

    expect(player.isSmartShuffle, isTrue);
    expect(player.queue, hasLength(10));
    expect(ids(), hasLength(10));
  });

  // RD: a Smart Shuffle queue is topped up from the song radio, or not at all, so it ends after its first ten songs.
  test('tops up a Smart Shuffle queue with new picks as it runs low', () async {
    await start(player.smartShuffle);
    await start(() => player.adoptTrackAt(8));
    final first = ids();

    await start(player.skipNext);

    expect(player.queue, hasLength(20));
    expect(ids(), hasLength(20), reason: 'no song queued twice');
    expect(ids().containsAll(first), isTrue);
  });

  // RD: a skip within the queue counts as starting a new one, so the first skip ends Smart Shuffle.
  test('a skip keeps Smart Shuffle going', () async {
    await start(player.smartShuffle);
    // Without the gapless source a skip replays the queue through playSong, the path that could end it.
    player.debugGaplessSource = null;
    await start(() => player.skipToIndex(3));

    expect(player.isSmartShuffle, isTrue);
  });

  // RD: once a radio or Smart Shuffle has run, every later queue (an album, a playlist) is topped up by it when it ends.
  test('playing another queue ends Smart Shuffle and the song radio', () async {
    final album = library.songs.take(3).toList();

    await start(player.smartShuffle);
    await start(() => player.playSong(album.last, playlist: album));
    expect(player.isSmartShuffle, isFalse);

    await start(() => player.playSongWithRadio(library.songs[20]));
    expect(player.isRadioQueue, isTrue);
    await start(() => player.playSong(album.first, playlist: album));
    expect(player.isRadioQueue, isFalse);
  });

  // RD: the shuffle toggle makes skips jump at random within the Smart Shuffle queue, so the same ten songs come
  // round again and again and the queue rarely reaches its end, where the next picks are added.
  test(
      'plays Smart Shuffle in order with the shuffle toggle on, refilling instead of repeating',
      () async {
    // After the player's start-up, which loads the saved shuffle setting over anything set before it.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    player.toggleShuffle(forceValue: true);
    await start(player.smartShuffle);
    expect(player.shuffleEnabled, isTrue);

    final heard = [player.currentSong!.id];
    for (var i = 0; i < 14; i++) {
      // Without the gapless source a skip moves through playSong, which tests can follow; each playSong builds a
      // new one.
      player.debugGaplessSource = null;
      await start(player.skipNext);
      heard.add(player.currentSong!.id);
    }

    expect(heard.toSet(), hasLength(15), reason: 'no song twice: $heard');
    expect(player.queue.length, greaterThan(10));
  });

  // RD: turning shuffle on during Smart Shuffle reshuffles its queue, putting songs already heard back ahead of
  // the current one.
  test('keeps a Smart Shuffle queue in its order when shuffle is turned on',
      () async {
    await start(player.smartShuffle);
    final order = ids();
    final queued = player.queue.map((s) => s.id).toList();

    player.toggleShuffle(forceValue: true);

    expect(player.queue.map((s) => s.id).toList(), queued);
    expect(ids(), order);
  });

  // RD: the shuffle button skips a state, or reaching Smart Shuffle leaves the plain shuffle flag on, so the next
  // tap lands on Shuffle instead of Off; or turning Smart Shuffle off discards the queue that is playing.
  test(
      'the shuffle button steps off, shuffle, Smart Shuffle, then off with the queue kept',
      () async {
    // After the player's start-up, which loads the saved shuffle setting over anything set before it.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(player.shuffleState, ShuffleState.off);

    await player.cycleShuffle();
    expect(player.shuffleState, ShuffleState.shuffle);

    await start(player.cycleShuffle);
    expect(player.shuffleState, ShuffleState.smart);
    expect(player.queue, hasLength(10));
    final picks = ids();

    await player.cycleShuffle();
    expect(player.shuffleState, ShuffleState.off);
    expect(player.shuffleEnabled, isFalse);
    expect(ids(), picks);
  });

  // RD: Smart Shuffle started from the Library while shuffle is on shows as Smart Shuffle, but one tap only stops
  // the refill and leaves plain shuffle on.
  test('one tap turns off a Smart Shuffle started with shuffle on', () async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    player.toggleShuffle(forceValue: true);
    await start(player.smartShuffle);
    expect(player.shuffleState, ShuffleState.smart);

    await player.cycleShuffle();

    expect(player.shuffleState, ShuffleState.off);
  });

  // RD: Smart Shuffle reached from Shuffle leaves plain shuffle on underneath, so the next album played comes out
  // shuffled although the button last showed Smart Shuffle.
  test(
      'playing another queue after Smart Shuffle from the button leaves shuffle off',
      () async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await player.cycleShuffle();
    await start(player.cycleShuffle);
    expect(player.shuffleState, ShuffleState.smart);

    final album = library.songs.take(3).toList();
    await start(() => player.playSong(album.first, playlist: album));

    expect(player.shuffleState, ShuffleState.off);
  });

  Future<RecommendationService> listenedTo(List<Song> skipped) async {
    final rec = RecommendationService();
    await rec.initialize();
    addTearDown(rec.dispose);
    for (final s in skipped) {
      await rec.trackSkip(s);
    }
    player.setRecommendationService(rec);
    return rec;
  }

  // RD: Smart Shuffle leaves out only songs played to the end, so songs the user just skipped are offered again
  // in the next queue.
  test('leaves out the songs just skipped', () async {
    final skipped = library.songs.take(20).toList();
    await listenedTo(skipped);

    await start(player.smartShuffle);

    expect(player.queue, hasLength(10));
    expect(ids().intersection(skipped.map((s) => s.id).toSet()), isEmpty);
  });

  // RD: the cooldown leaves a library heard all through with nothing to play; or it lets back more heard songs
  // than the queue needs, or the ones heard last instead of those heard longest ago.
  test(
      'fills the queue from the songs heard longest ago, only as many as needed',
      () async {
    final heard = library.songs.take(25).toList();
    await listenedTo(heard);

    await start(player.smartShuffle);

    expect(player.queue, hasLength(10));
    final heardLast = heard.reversed.take(20).map((s) => s.id).toSet();
    expect(ids().intersection(heardLast), isEmpty,
        reason: 'five unheard songs and the five heard longest ago fill it');
  });

  // RD: only this device's listens are left out, so songs heard on the phone this week are queued on the desktop;
  // or the server's list is taken whole, songs heard before the week included.
  test('leaves out the songs heard on other devices this week', () async {
    final now = DateTime.now();
    server.recentlyHeard = [
      for (final s in library.songs.take(15))
        (id: s.id, at: now.subtract(const Duration(hours: 5))),
      (id: library.songs[20].id, at: now.subtract(const Duration(days: 8))),
    ];
    await listenedTo(const []);

    await start(player.smartShuffle);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(player.queue, hasLength(10));
    expect(ids().intersection(library.songs.take(15).map((s) => s.id).toSet()),
        isEmpty);
    // The server is asked for the week only (milliseconds since the epoch), not the whole history.
    final since = DateTime.fromMillisecondsSinceEpoch(
        int.parse(server.lastParams['getRecentlyHeard']!['since']!.single));
    expect(now.difference(since).inHours, inInclusiveRange(167, 169));
  });

  // RD: moving the slider only applies from the next refill, so the songs queued next ignore it; or it replaces
  // the playing song; or the position is not saved, and a restart puts the slider back in the middle.
  test(
      'moving the slider re-picks the songs after the current one, and is kept',
      () async {
    await start(player.smartShuffle);
    final playing = player.currentSong;

    await start(() => player.setSmartShuffleTaste(0));

    expect(player.currentSong, playing);
    expect(player.queue.first, playing);
    final upcoming = [
      for (final s in player.queue.skip(1))
        player.debugPickReasonOf(s.id) as ShufflePick
    ];
    expect(upcoming, isNotEmpty);
    expect(upcoming.every((r) => r.taste == 0), isTrue);

    final again = PlayerProvider(
        SubsonicService(),
        StorageService(),
        FakeCastService(),
        UpnpService(),
        MuslyAudioHandler(),
        JukeboxService(),
        TranscodingService());
    addTearDown(again.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(again.smartShuffleTaste, 0.0);
  });
}
