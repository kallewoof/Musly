import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/song.dart';
import '../providers/player_provider.dart';
import 'subsonic_service.dart';

/// Tells an OpenSubsonic server how listens go (`reportPlayback`), so it can count each song's skips and
/// completions per user. The reports are derived from the player's state (current song, playing, position)
/// rather than from its many track-change paths.
class PlaybackReporter {
  PlaybackReporter(this._player, this._service);

  final PlayerProvider _player;
  final SubsonicService _service;

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

  /// The song is being replaced. Left while paused it gets no verdict: the queue was adopted from another
  /// device or restored, or the listen was already abandoned. Past 90% it was heard, however it ended.
  void _leave() {
    final left = _song;
    if (left == null || !_started) return;
    final seconds = left.duration ?? 0;
    final heard = seconds > 0 && _position.inMilliseconds >= seconds * 900;
    if (_playing || heard) _send(left, 'stopped', _position);
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
