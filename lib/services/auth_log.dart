import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// An on-device record of how each start found the saved login and why the app ever asked for one, so an
/// unexpected sign-out can be explained afterwards. It stays on the device (on iOS, read from the app's
/// container with devicectl) and never holds a secret.
class AuthLog {
  AuthLog._();
  static final AuthLog instance = AuthLog._();

  /// The newest lines kept.
  static const int maxLines = 300;

  @visibleForTesting
  Future<File> Function() file = () async =>
      File('${(await getApplicationSupportDirectory()).path}/auth_log.txt');

  Future<void> _writes = Future.value();

  /// Appends [event] with the time and the app's lifecycle state (a start in the background shows here).
  /// Never throws: the log must not stand in the way of signing in.
  Future<void> record(String event) {
    final line = '${DateTime.now().toIso8601String()} '
        '[${WidgetsBinding.instance.lifecycleState?.name ?? 'starting'}] $event';
    debugPrint('[AuthLog] $line');
    return _writes = _writes
        .then((_) => _append(line))
        .catchError((Object e) => debugPrint('[AuthLog] not written: $e'));
  }

  Future<void> _append(String line) async {
    final f = await file();
    final lines = await f.exists() ? await f.readAsLines() : <String>[];
    lines.add(line);
    final kept = lines.skip(math.max(0, lines.length - maxLines));
    await f.parent.create(recursive: true);
    await f.writeAsString('${kept.join('\n')}\n');
  }
}
