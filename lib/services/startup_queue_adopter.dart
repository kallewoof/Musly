import 'dart:async';

import '../providers/auth_provider.dart';
import '../providers/player_provider.dart';

/// Takes over the queue another device left on the server once per start, as soon as the app is signed in.
/// Otherwise a fresh start shows the song this device last played, until play is pressed: a start is not a
/// return to the foreground, which is the other time a queue is adopted.
class StartupQueueAdopter {
  StartupQueueAdopter(this._auth, this._player);

  final AuthProvider _auth;
  final PlayerProvider _player;

  void start() {
    _auth.addListener(_onChange);
    _onChange();
  }

  void _onChange() {
    if (!_auth.isAuthenticated) return;
    _auth.removeListener(_onChange);
    unawaited(_player.adoptRemoteQueueAtStart());
  }
}
