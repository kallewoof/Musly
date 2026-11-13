import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../providers/player_provider.dart';

/// Connects the iOS lock-screen "Favourite song" control (`ios/MuslyWidgets`) to the player: tells it whether
/// the current song is starred, and stars or unstars that song when the control is pressed.
class FavoriteControlService {
  FavoriteControlService(this._player, {MethodChannel? channel})
      : _channel =
            channel ?? const MethodChannel('com.devid.musly/favorite_control');

  final PlayerProvider _player;
  final MethodChannel _channel;
  bool? _sentStarred;

  void start() {
    _channel.setMethodCallHandler(_handle);
    _player.addListener(_publish);
    _publish();
  }

  Future<void> _handle(MethodCall call) async {
    if (call.method != 'toggle') {
      throw MissingPluginException(
          'favorite_control has no method ${call.method}');
    }
    await _player.toggleFavorite();
  }

  /// The player notifies on every position tick; only a change in what the control shows crosses the channel.
  void _publish() {
    final starred = _player.currentSong?.starred == true;
    if (starred == _sentStarred) return;
    _sentStarred = starred;
    unawaited(_channel.invokeMethod<void>(
        'setState', {'starred': starred}).catchError((Object e) {
      debugPrint('[FavoriteControl] setState failed: $e');
    }));
  }
}
