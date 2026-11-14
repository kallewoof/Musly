import 'dart:async';

import 'package:flutter/widgets.dart';

import '../providers/player_provider.dart';

/// Asks the server for the current song's star whenever the song changes or the app returns to the
/// foreground (another device may have starred it meanwhile), so the heart and the lock-screen control
/// show the server's state rather than the queue's copy.
class StarRefresher with WidgetsBindingObserver {
  StarRefresher(this._player);

  final PlayerProvider _player;
  String? _songId;

  void start() {
    _player.addListener(_onChange);
    WidgetsBinding.instance.addObserver(this);
    _onChange();
  }

  void _onChange() {
    final id = _player.currentSong?.id;
    if (id == _songId) return;
    _songId = id;
    if (id != null) unawaited(_player.refreshCurrentStar());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _songId != null) {
      unawaited(_player.refreshCurrentStar());
    }
  }
}
