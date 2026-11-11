import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musly/models/server_config.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';

ServerConfig _config(String url) =>
    ServerConfig(serverUrl: url, username: 'u', password: 'p');

/// A fresh install: empty preferences, which StorageService (a singleton) must be rebound to.
Future<void> _freshInstall() async {
  SharedPreferences.setMockInitialValues({});
  await StorageService().init();
}

String _clientParam(SubsonicService service) =>
    Uri.parse(service.getStreamUrl('song1')).queryParameters['c']!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('per-install client name', () {
    // RD: the install id is regenerated on every launch, so each restart looks like a new device and a
    // queue this device saved is adopted back as if another device had left it.
    test('is the same across restarts of one install', () async {
      await _freshInstall();
      final first = SubsonicService();
      await first.configure(_config('http://server'));
      final second = SubsonicService();
      await second.configure(_config('http://server'));

      expect(_clientParam(first), startsWith('Musly-'));
      expect(_clientParam(second), _clientParam(first));
    });

    // RD: the client name falls back to the shared constant, so every device reports itself as "Musly" and
    // a queue left by the phone is indistinguishable from one this desktop saved.
    test('differs between installs', () async {
      await _freshInstall();
      final a = SubsonicService();
      await a.configure(_config('http://server'));
      await _freshInstall();
      final b = SubsonicService();
      await b.configure(_config('http://server'));

      expect(_clientParam(a), isNot(_clientParam(b)));
    });
  });

  group('User-Agent', () {
    late HttpServer server;
    late List<String?> userAgents;

    setUp(() async {
      userAgents = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        userAgents.add(req.headers.value(HttpHeaders.userAgentHeader));
        req.response
          ..headers.contentType = ContentType.json
          ..write('{"subsonic-response":{"status":"ok","version":"1.16.1"}}')
          ..close();
      });
    });

    tearDown(() => server.close(force: true));

    // RD: the Dio rebuilt for certificate settings at configure time drops the header, so API calls go out
    // as Dart's default agent, which Cloudflare's bot checks have blocked on this zone.
    test('is Musly\'s own on API requests after configure', () async {
      await _freshInstall();
      final service = SubsonicService();
      await service.configure(_config('http://127.0.0.1:${server.port}'));

      expect(await service.ping(), isTrue);

      expect(userAgents, isNotEmpty);
      expect(userAgents.last, startsWith('Musly/'));
      expect(userAgents.last, isNot(contains('dart')));
    });
  });
}
