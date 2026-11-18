import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'song.dart';

/// The server's saved play queue (one per user), as `getPlayQueueByIndex` returns it.
class RemotePlayQueue {
  const RemotePlayQueue({
    required this.songs,
    required this.currentIndex,
    required this.position,
    required this.changed,
    required this.changedBy,
    this.state,
  });

  final List<Song> songs;
  final int currentIndex;
  final Duration position;

  /// The server's own timestamp, compared only for equality: device clocks never enter into it.
  final String changed;

  /// The client name of the install that saved it.
  final String changedBy;

  /// How the saving device played the queue (shuffle, refill, pick reasons); null when it sent none.
  final Map<String, dynamic>? state;

  /// Null for an empty queue, or one whose current index does not point into it.
  static RemotePlayQueue? fromJson(Map<String, dynamic> json) {
    final entries = json['entry'] as List<dynamic>? ?? const [];
    final index = json['currentIndex'] as int?;
    if (entries.isEmpty ||
        index == null ||
        index < 0 ||
        index >= entries.length) {
      return null;
    }
    return RemotePlayQueue(
      songs:
          entries.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList(),
      currentIndex: index,
      position:
          Duration(milliseconds: (json['position'] as num?)?.toInt() ?? 0),
      changed: json['changed'] as String? ?? '',
      changedBy: json['changedBy'] as String? ?? '',
      state: _state(json['unimouseState']),
    );
  }

  /// The server keeps the state a JSON object; anything else is reported and the queue taken without it.
  static Map<String, dynamic>? _state(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[RemotePlayQueue] unreadable unimouseState: $e');
      return null;
    }
  }
}
