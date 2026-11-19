import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
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

/// How the player hands each song it leaves to the playback reporter, which judges the listen.
void main() {
  initializeTestEnvironment();

  late FakeQueueServer server;
  late PlayerProvider player;
  late List<Song> songs;

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
    songs = [
      for (var i = 0; i < 8; i++)
        Song(id: 's$i', title: 'T$i', artist: 'A${i % 6}', duration: 200),
    ];
    player.setLibraryProvider(_Library(service, songs));
    // After the player's start-up, which loads the saved shuffle setting over anything set before it.
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });

  tearDown(() async {
    player.dispose();
    await server.stop();
  });

  /// Runs [action], which loads audio that tests cannot play: the guarded zone absorbs that.
  Future<void> run(FutureOr<void> Function() action) async {
    // Without the gapless source a move goes through playSong, which tests can follow.
    player.debugGaplessSource = null;
    runZonedGuarded(() => action(), (_, __) {});
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  // RD: Back is not marked, so going back to hear the previous song again counts the song left as skipped; or
  // the mark lingers, and the next song left with Next gets no verdict either.
  test('marks a song left with Back, and only that one', () async {
    await run(() => player.playSong(songs[2],
        playlist: songs.take(5).toList(), startIndex: 2));

    await run(player.skipNext);
    expect(player.lastLeft?.id, 's2');
    expect(player.lastLeft?.unjudged, isFalse);

    await run(player.skipPrevious);
    expect(player.currentSong?.id, 's2');
    expect(player.lastLeft?.id, 's3');
    expect(player.lastLeft?.unjudged, isTrue);

    await run(player.skipNext);
    expect(player.lastLeft?.id, 's2');
    expect(player.lastLeft?.unjudged, isFalse);
  });

  // RD: Back on the first song (which only restarts it) leaves the mark set, so the song after it, left with
  // Next, gets no verdict.
  test('clears the mark when Back stays on the same song', () async {
    await run(() => player.playSong(songs[0],
        playlist: songs.take(5).toList(), startIndex: 0));

    await run(player.skipPrevious);
    await run(player.skipNext);

    expect(player.lastLeft?.id, 's0');
    expect(player.lastLeft?.unjudged, isFalse);
  });

  // RD: the player records each song it leaves as a finished listen (or each start as a listen), so skipped
  // songs look as liked as songs heard through.
  test('records no listen itself when the song changes', () async {
    final rec = RecommendationService();
    await rec.initialize();
    addTearDown(rec.dispose);
    player.setRecommendationService(rec);
    await run(() => player.playSong(songs[0],
        playlist: songs.take(5).toList(), startIndex: 0));

    await run(player.skipNext);
    await run(player.skipNext);

    expect(rec.listenOutcomes(songs[0]), (completes: 0, skips: 0));
    expect(rec.recentlyPlayed, isEmpty);
  });

  // RD: with the shuffle toggle on, Back in Smart Shuffle goes to a random queued song, as it does in a
  // shuffled queue, instead of the song before.
  test('goes back to the song before in Smart Shuffle, with shuffle on',
      () async {
    player.toggleShuffle(forceValue: true);
    await run(player.smartShuffle);
    await run(player.skipNext);
    await run(player.skipNext);
    final before = player.queue[player.currentIndex - 1].id;

    await run(player.skipPrevious);

    expect(player.isSmartShuffle, isTrue);
    expect(player.currentSong?.id, before);
  });

  /// Plays songs[2] of the first six, with a gapless source standing in for the one audio would build.
  Future<ConcatenatingAudioSource> playingThird() async {
    await run(() => player.playSong(songs[2],
        playlist: songs.take(6).toList(), startIndex: 2));
    final source = ConcatenatingAudioSource(children: [
      for (final s in player.queue)
        AudioSource.uri(Uri.parse('http://test/${s.id}'), tag: s.id),
    ]);
    player.debugGaplessSource = source;
    return source;
  }

  /// The queue edits behind the shuffle button finish in the background.
  Future<void> settled() =>
      Future<void>.delayed(const Duration(milliseconds: 200));

  List<Object?> tags(ConcatenatingAudioSource s) =>
      [for (final c in s.children) (c as UriAudioSource).tag];

  // RD: turning shuffle on rebuilds the gapless source, which restarts the playing song from the start; or the
  // source is edited out of step with the queue, so the next song played is not the one shown next.
  test('turning shuffle on keeps the playing song and reorders the rest',
      () async {
    final source = await playingThird();

    await player.cycleShuffle();
    await settled();

    expect(player.shuffleState, ShuffleState.shuffle);
    expect((player.currentSong?.id, player.currentIndex), ('s2', 0));
    expect(identical(player.debugGaplessSource, source), isTrue,
        reason: 'a new source restarts the song');
    expect(tags(source), [for (final s in player.queue) s.id]);
    expect({for (final s in player.queue) s.id},
        {for (final s in songs.take(6)) s.id});
  });

  // RD: Smart Shuffle starts its queue with a song of its own, so the song playing is cut off and counted as a
  // skip; or it keeps the song but leaves the old queue after it.
  test('starting Smart Shuffle keeps the playing song, with the picks after it',
      () async {
    final source = await playingThird();
    final before = player.lastLeft;

    // Clicked twice in quick succession: the second click's edit starts before the first one's is done.
    await player.cycleShuffle();
    await player.cycleShuffle();
    await settled();

    expect(player.shuffleState, ShuffleState.smart);
    expect((player.currentSong?.id, player.currentIndex), ('s2', 0));
    expect(player.lastLeft, before, reason: 'no song was left');
    expect(identical(player.debugGaplessSource, source), isTrue);
    expect(tags(source), [for (final s in player.queue) s.id]);
    final picks = player.queue.skip(1).map((s) => s.id).toList();
    expect(picks, isNotEmpty);
    expect(picks, isNot(contains('s2')));
  });

  /// The ids sent to the server as plays (scrobble submissions).
  List<String> plays() => [
        for (final s in server.scrobbles)
          if (s['submission']?.single == 'true') s['id']!.single,
      ];

  /// Two short songs, the first playing past its scrobble point (half of its 2 s).
  Future<List<Song>> heardFirstOfTwo() async {
    final short = [
      Song(id: 'x0', title: 'X0', duration: 2),
      Song(id: 'x1', title: 'X1', duration: 2),
    ];
    await run(() => player.playSong(short[0], playlist: short, startIndex: 0));
    player.debugSetPlaying(true);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    return short;
  }

  // RD: only the gapless index change and a natural end send the play, so a song heard through and left by
  // another path (a new queue, a pick, a stuck song passed over) is never counted as played, and is missing
  // from what other devices count as heard this week.
  test(
      'a song heard past its scrobble point counts as played, however it is left',
      () async {
    final short = await heardFirstOfTwo();

    await run(() => player.playSong(short[1], playlist: short, startIndex: 1));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(plays(), ['x0']);
    expect(player.lastLeft?.heard,
        greaterThanOrEqualTo(const Duration(milliseconds: 1000)),
        reason: 'the playback reporter judges the listen by this');

    // The next song's listen is a play of its own.
    player.debugSetPlaying(true);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await run(() => player.playSong(short[0], playlist: short, startIndex: 0));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(plays(), ['x0', 'x1']);
  });

  // RD: the play is sent from every path that leaves the song, so one listen counts as two plays.
  test('a listen is sent as a play once, whichever paths retire it', () async {
    final short = await heardFirstOfTwo();

    player.retireCurrentTrack();
    await run(() => player.playSong(short[1], playlist: short, startIndex: 1));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(plays(), ['x0']);
  });

  // RD: leaving a song counts it as played whatever was heard, so skipped songs gain plays.
  test('a song left before its scrobble point is not a play', () async {
    final short = [
      Song(id: 'x0', title: 'X0', duration: 200),
      Song(id: 'x1', title: 'X1', duration: 200),
    ];
    await run(() => player.playSong(short[0], playlist: short, startIndex: 0));
    player.debugSetPlaying(true);

    await run(() => player.playSong(short[1], playlist: short, startIndex: 1));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(plays(), isEmpty);
  });
}
