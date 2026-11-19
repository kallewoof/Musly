import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/song.dart';
import '../providers/player_provider.dart';
import 'recommendation_service.dart';
import 'subsonic_service.dart';

/// Judges how each listen ended and passes the verdict on: to an OpenSubsonic server (`reportPlayback`), which
/// counts each song's skips and completions per user, and to this device's taste model. The reports are derived
/// from the player's state (current song, playing, position) rather than from its many track-change paths.
class PlaybackReporter {
  PlaybackReporter(this._player, this._service,
      {RecommendationService? recommendations})
      : _recommendations = recommendations;

  final PlayerProvider _player;
  final SubsonicService _service;
  final RecommendationService? _recommendations;

  Song? _song;
  bool _started = false;
  bool _playing = false;
  Duration _position = Duration.zero;

  /// Reports go out one at a time: the server ignores a song's `stopped` once the next song has started.
  Future<void> _chain = Future.value();

  void start() {
    _player.addListener(_onChange);
    _onChange();
  }

  void _onChange() {
    final song = _player.currentSong;
    if (song?.id != _song?.id) {
      _leave();
      _song = song;
      _started = false;
      _playing = false;
    }
    final playing = _player.isPlaying;
    final position = _player.position;
    if (_song != null && playing != _playing) {
      _send(_song!, playing ? (_started ? 'playing' : 'starting') : 'paused',
          position);
      _started = true;
    }
    _playing = playing;
    _position = position;
  }

  /// The song is being replaced. Left with Back, past a song that never started, or while paused, it gets no
  /// verdict: going back is to hear an earlier song again, a song that never played was not heard, and a paused
  /// song was replaced by an adopted or restored queue, or already abandoned.
  /// A finished listen (_verdict) was heard, however it ended. How long it was heard comes from the player, which counts it by
  /// the clock; the position seen here can be stale, as position changes do not notify listeners.
  void _leave() {
    final left = _song;
    if (left == null || !_started) return;
    final handed = _player.lastLeft;
    final fromPlayer = handed != null && handed.id == left.id;
    if (fromPlayer && handed.unjudged) return;
    final heard = fromPlayer ? handed.heard : _position;
    final verdict = _verdict(left.duration ?? 0, heard);
    if (!_playing && verdict != _Verdict.finished) return;
    _judge(left, heard, verdict);
    _send(left, 'stopped', heard);
  }

  /// The verdict the server draws from the stop: a skip before the scrobble point (half the song, at most four
  /// minutes); a finish from 90% of the song or its last 30 seconds, whichever comes first; between them, or for
  /// a song of unknown length, a listen that counts as neither.
  static _Verdict _verdict(int seconds, Duration heard) {
    if (seconds <= 0) return _Verdict.neither;
    final ms = heard.inMilliseconds;
    final durationMs = seconds * 1000;
    if (ms < min(seconds * 500, 240000)) return _Verdict.skipped;
    if (ms >= min(durationMs * 9 ~/ 10, durationMs - 30000)) {
      return _Verdict.finished;
    }
    return _Verdict.neither;
  }

  /// The taste model takes the same verdict as the server.
  void _judge(Song song, Duration heard, _Verdict verdict) {
    final rec = _recommendations;
    if (rec == null) return;
    switch (verdict) {
      case _Verdict.finished:
        rec.trackSongPlay(song,
            durationPlayed: heard.inSeconds, completed: true);
      case _Verdict.skipped:
        rec.trackSkip(song, secondsPlayed: heard.inSeconds);
      case _Verdict.neither:
        rec.trackSongPlay(song, durationPlayed: heard.inSeconds);
    }
  }

  void _send(Song song, String state, Duration position) {
    if (song.isLocal) return;
    _chain = _chain.then((_) async {
      try {
        if (!await _available()) return;
        await _service.reportPlayback(song.id, state, position);
      } catch (e) {
        debugPrint('[PlaybackReporter] $state for ${song.id} failed: $e');
      }
    });
  }

  Future<bool> _available() async =>
      _service.isConfigured &&
      !_service.isJellyfin &&
      !_service.isYoutube &&
      (await _service.openSubsonicExtensions()).contains('playbackReport');
}

enum _Verdict { skipped, neither, finished }
