import 'package:flutter_test/flutter_test.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:audio_service/audio_service.dart';

import '../bootstrap.dart';

/// The media session is what the notification, lock screen, Android Auto and a
/// car head unit all read. If the handler cannot publish remote playback state
/// into it, every one of those controls silently operates on the idle local
/// player instead of the Cast/DLNA renderer.
///
/// That is exactly what happened: the constructor used
/// `playbackEventStream.pipe(playbackState)`, and pipe() is addStream() on the
/// underlying rxdart Subject — so every other playbackState.add() in the class
/// threw "You cannot add items while items are being added from addStream".
void main() {
  initializeTestEnvironment();

  late MuslyAudioHandler handler;

  setUp(() => handler = MuslyAudioHandler());
  tearDown(() => handler.cancelLocalStateMirror());

  test('updateRemotePlaybackState publishes instead of throwing', () {
    expect(
      () => handler.updateRemotePlaybackState(
        playing: true,
        position: const Duration(seconds: 42),
      ),
      returnsNormally,
      reason: 'a pipe()d playbackState makes every add() throw',
    );

    expect(handler.playbackState.value.playing, isTrue);
    expect(handler.playbackState.value.updatePosition,
        const Duration(seconds: 42));
  });

  test('remote pause state reaches the session', () {
    handler.updateRemotePlaybackState(
      playing: false,
      position: const Duration(seconds: 10),
    );
    expect(handler.playbackState.value.playing, isFalse);
    expect(handler.playbackState.value.systemActions, contains(MediaAction.setShuffleMode));
    expect(handler.playbackState.value.systemActions, contains(MediaAction.setRepeatMode));
  });

  test('repeated remote updates keep working', () {
    // A 1 Hz poll drives this continuously; one throw would leave the session
    // frozen for the rest of the session.
    for (var i = 1; i <= 20; i++) {
      handler.updateRemotePlaybackState(
        playing: true,
        position: Duration(seconds: i),
      );
    }
    expect(handler.playbackState.value.updatePosition,
        const Duration(seconds: 20));
  });

  test('disposal cancels the local state mirror', () async {
    expect(handler.isMirroringLocalState, isTrue);

    await handler.customAction('dispose');

    expect(handler.isMirroringLocalState, isFalse,
        reason: 'AudioPlayer.dispose() does not cancel our own subscription '
            'to its event stream, so the handler must do it');
  });

  test('cancelling the mirror twice is safe', () async {
    await handler.cancelLocalStateMirror();
    await handler.cancelLocalStateMirror();
    expect(handler.isMirroringLocalState, isFalse);
  });

  test('updateNowPlaying publishes media item metadata', () {
    handler.updateNowPlaying(
      id: 'song-1',
      title: 'Track',
      artist: 'Artist',
      duration: const Duration(minutes: 3),
    );
    expect(handler.mediaItem.value?.id, 'song-1');
    expect(handler.mediaItem.value?.title, 'Track');
  });

  // RD: a stop while paused (the route changing on leaving home, another device's queue adopted) is published
  // as idle, which stops audio_service's service: Musly vanishes from the iOS lock screen and the AirPods
  // buttons start Apple Music instead.
  test('a stopped player with a current song is published as paused, not idle',
      () {
    handler.updateNowPlaying(id: 'song-1', title: 'Track');
    handler.playbackState
        .add(PlaybackState(updatePosition: const Duration(seconds: 84)));

    final state = handler.buildPlaybackState(handler.player.playbackEvent);
    expect(state.processingState, AudioProcessingState.ready);
    expect(state.playing, isFalse);
    expect(state.updatePosition, const Duration(seconds: 84));
  });

  // RD: the paused hold also covers a cleared queue, so after clearing it (or switching servers) the lock
  // screen keeps offering a song that is gone.
  test('a stopped player without a current song is published as idle', () {
    handler.updateNowPlaying(id: 'song-1', title: 'Track');
    handler.clearNowPlaying();

    final state = handler.buildPlaybackState(handler.player.playbackEvent);
    expect(state.processingState, AudioProcessingState.idle);
  });
}
