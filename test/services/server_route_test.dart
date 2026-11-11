import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musly/models/server_config.dart';
import 'package:musly/services/server_route_watcher.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';

/// A server on loopback. [subsonic] false makes it answer like a captive portal: 200 with an HTML page.
class _Server {
  _Server({this.subsonic = true});

  bool subsonic;
  Duration delay = Duration.zero;
  late HttpServer _server;
  int requests = 0;

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      requests++;
      await Future<void>.delayed(delay);
      if (subsonic) {
        req.response
          ..headers.contentType = ContentType.json
          ..write('{"subsonic-response":{"status":"ok","version":"1.16.1"}}');
      } else {
        req.response
          ..headers.contentType = ContentType.html
          ..write('<html><body>Sign in to the Wi-Fi</body></html>');
      }
      req.response.close();
    });
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Server lan;
  late _Server wan;
  late SubsonicService service;

  Future<void> configure() => service.configure(ServerConfig(
        serverUrl: wan.url,
        lanUrl: lan.url,
        username: 'u',
        password: 'p',
      ));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().init();
    lan = _Server();
    wan = _Server();
    await lan.start();
    await wan.start();
    service = SubsonicService();
  });

  tearDown(() async {
    await lan.stop();
    await wan.stop();
  });

  // RD: the probe's answer is not applied, so a desktop at home streams everything through Cloudflare.
  test('uses the LAN address while it answers', () async {
    await configure();

    expect(service.activeBaseUrl, lan.url);
  });

  // RD: any 200 counts as the server answering, so on a network whose captive portal sits at the same
  // private address, every request goes to the portal and nothing plays.
  test('does not take a captive portal on the LAN address for the server',
      () async {
    lan.subsonic = false;

    await configure();

    expect(service.activeBaseUrl, wan.url);
  });

  // RD: a laptop that leaves home with the app running keeps sending every request to the unreachable LAN
  // address until it is restarted.
  test('falls back to the public address when the LAN address stops answering',
      () async {
    await configure();
    await lan.stop();

    expect(await service.ping(), isTrue);

    expect(service.activeBaseUrl, wan.url);
    expect(wan.requests, greaterThan(0));
  });

  // RD: a slow LAN check for the previous server finishes after a switch to another server and points the
  // new server's requests at the old address.
  test('a route check finished after a server switch does not redirect it',
      () async {
    await configure();
    lan.delay = const Duration(milliseconds: 300);
    final staleCheck = service.refreshRoute();

    final other = _Server();
    await other.start();
    await service.configure(
        ServerConfig(serverUrl: other.url, username: 'u', password: 'p'));
    await staleCheck;

    expect(service.activeBaseUrl, other.url);
    await other.stop();
  });

  group('ServerRouteWatcher', () {
    late StreamController<List<ConnectivityResult>> changes;
    late ServerRouteWatcher watcher;

    setUp(() async {
      lan.subsonic = false;
      await configure();
      expect(service.activeBaseUrl, wan.url);
      lan.subsonic = true;
      changes = StreamController();
      watcher = ServerRouteWatcher(service, connectivityChanges: changes.stream)
        ..start();
    });

    tearDown(() async {
      watcher.dispose();
      await changes.close();
    });

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 200));

    // RD: the connectivity subscription is never made, so a laptop that joins the home Wi-Fi keeps going
    // through Cloudflare until it is restarted.
    test('moves to the LAN address after a connectivity change', () async {
      changes.add([ConnectivityResult.wifi]);
      await settle();

      expect(service.activeBaseUrl, lan.url);
    });

    // RD: a laptop that wakes at home reports no connectivity change, so only returning to the foreground
    // can notice the LAN address is back.
    test('moves to the LAN address when the app returns to the foreground',
        () async {
      watcher.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();

      expect(service.activeBaseUrl, lan.url);
    });
  });
}
