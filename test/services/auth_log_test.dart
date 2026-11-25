import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musly/services/auth_log.dart';

import '../bootstrap.dart';

void main() {
  initializeTestEnvironment();

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('musly_auth_log_');
    AuthLog.instance.file = () async => File('${dir.path}/auth_log.txt');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  // RD: the log is appended to forever, so a phone that starts the app in the background many times a day fills
  // its storage; or the trim keeps the oldest lines, so the sign-out being explained is the one dropped.
  test('keeps only the newest lines', () async {
    for (var i = 0; i < AuthLog.maxLines + 5; i++) {
      AuthLog.instance.record('event $i');
    }
    await AuthLog.instance.record('last');

    final lines = await File('${dir.path}/auth_log.txt').readAsLines();
    expect(lines, hasLength(AuthLog.maxLines));
    expect(lines.first, endsWith('event 6'));
    expect(lines.last, endsWith('last'));
  });
}
