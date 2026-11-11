import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'subsonic_service.dart';

/// Keeps the user's server-side play queue in step with this device, so playback stopped on one device
/// resumes on another at the same song and position.
///
/// The rules that keep one device from clobbering another:
/// - only a local change is pushed ([markChanged]), never a queue that was merely restored, and never an
///   empty one: a fresh or offline install that goes to the background must not overwrite the queue
///   another device left;
/// - a remote queue is offered ([takeForeign]) only when another install saved it and this install has
///   not yet adopted that save (the server's `changed` stamp, compared for equality only); and
/// - while a local change is still unsent, this device's queue is the newer one: it is pushed instead.
class PlayQueueSync {
  PlayQueueSync(this._service);

  final SubsonicService _service;

  static const _keyAdopted = 'play_queue_adopted_changed';

  _Snapshot? _pending;
  Future<void>? _inFlight;

  bool get _available =>
      _service.isConfigured && !_service.isJellyfin && !_service.isYoutube;

  bool get hasUnsentChange => _pending != null;

  /// Records this device's queue as changed. Nothing is sent until [flush]: the caller decides when a
  /// change is worth a request (pause, backgrounding, a periodic tick).
  void markChanged(List<Song> queue, int currentIndex, Duration position) {
    final snapshot = _Snapshot.of(queue, currentIndex, position);
    if (snapshot == null) return;
    _pending = snapshot;
  }

  /// Pushes the unsent change, if any, now. A failed push stays pending for the next attempt.
  Future<void> flush() async {
    await _inFlight;
    final snapshot = _pending;
    if (snapshot == null || !_available) return;
    _inFlight = () async {
      try {
        await _service.savePlayQueue(
            snapshot.songIds, snapshot.currentIndex, snapshot.position);
        if (identical(_pending, snapshot)) _pending = null;
      } catch (e) {
        debugPrint('[PlayQueueSync] push failed, kept pending: $e');
      }
    }();
    await _inFlight;
  }

  /// The server's queue, when another install saved it after this install last adopted one. Call
  /// [adopted] once it is applied; until then the same queue is offered again.
  Future<RemotePlayQueue?> takeForeign() async {
    if (!_available) return null;
    if (_pending != null) {
      await flush();
      return null;
    }
    final RemotePlayQueue? remote;
    try {
      remote = await _service.getPlayQueue();
    } catch (e) {
      debugPrint('[PlayQueueSync] fetch failed: $e');
      return null;
    }
    if (remote == null) return null;
    if (remote.changedBy == _service.identity.clientName) return null;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_keyAdopted) == remote.changed) return null;
    return remote;
  }

  Future<void> adopted(RemotePlayQueue remote) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAdopted, remote.changed);
  }
}

class _Snapshot {
  const _Snapshot(this.songIds, this.currentIndex, this.position);

  final List<String> songIds;
  final int currentIndex;
  final Duration position;

  /// Only server songs can be named to the server; local files are dropped and the index follows the
  /// current song. Null when nothing can be pushed: an empty queue, or a current song that is local.
  static _Snapshot? of(List<Song> queue, int currentIndex, Duration position) {
    if (currentIndex < 0 || currentIndex >= queue.length) return null;
    if (queue[currentIndex].isLocal) return null;
    final ids = <String>[];
    var index = -1;
    for (var i = 0; i < queue.length; i++) {
      if (queue[i].isLocal) continue;
      if (i == currentIndex) index = ids.length;
      ids.add(queue[i].id);
    }
    return _Snapshot(ids, index, position);
  }
}
