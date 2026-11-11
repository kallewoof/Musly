import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:musly/models/server_config.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';

/// A Subsonic server that records star and unstar requests, and can go down (connections refused) and
/// come back on the same port.
class _StarServer {
  HttpServer? _server;
  late int port;
  final calls = <String>[];
  bool refuse = false;

  /// An HTTP status other than 200, as a proxy in front of a restarting server answers.
  int? httpStatus;

  /// Delays every answer (after recording the call), to let a test act while a request is in flight.
  Duration delay = Duration.zero;

  Future<void> up() async {
    _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4, _server == null ? 0 : port);
    port = _server!.port;
    _server!.listen((req) async {
      final op = req.uri.pathSegments.last;
      if (httpStatus != null) {
        req.response.statusCode = httpStatus!;
        await req.response.close();
        return;
      }
      if (op == 'star' || op == 'unstar') {
        final q = req.uri.queryParameters;
        calls.add('$op ${q['id'] ?? q['albumId'] ?? q['artistId']}');
      }
      await Future<void>.delayed(delay);
      req.response
        ..headers.contentType = ContentType.json
        ..write(refuse
            ? '{"subsonic-response":{"status":"failed","error":{"code":70,"message":"not found"}}}'
            : '{"subsonic-response":{"status":"ok"}}');
      req.response.close();
    });
  }

  Future<void> down() => _server!.close(force: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _StarServer server;
  late SubsonicService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService().init();
    server = _StarServer();
    await server.up();
    service = SubsonicService();
    await service.configure(ServerConfig(
        serverUrl: 'http://127.0.0.1:${server.port}',
        username: 'u',
        password: 'p'));
  });

  tearDown(() => server.down().catchError((_) {}));

  // RD: a star made while the server is unreachable throws and is lost, so the favourite never reaches
  // the other devices.
  test('a star made while unreachable is sent once the server is back',
      () async {
    await server.down();

    await service.star(id: 'song1');

    await server.up();
    await service.flushPendingStars();

    expect(server.calls, ['star song1']);
  });

  // RD: every offline action is replayed, and when they are replayed out of order the item ends starred
  // although the user's last action was to unstar it.
  test('only the latest offline action on an item is sent', () async {
    await server.down();
    await service.star(id: 'song1');
    await service.unstar(id: 'song1');

    await server.up();
    await service.flushPendingStars();

    expect(server.calls, ['unstar song1']);
  });

  // RD: an action that reaches the server leaves the older offline one queued, so the next flush stars
  // again what the user has just unstarred.
  test('an action that reaches the server clears the older pending one',
      () async {
    await server.down();
    await service.star(id: 'song1');
    await server.up();

    await service.unstar(id: 'song1');
    await service.flushPendingStars();

    expect(server.calls, ['unstar song1']);
  });

  // RD: a flush that fails partway forgets the actions it did not get to, so they are lost for good.
  test('a flush that cannot reach the server keeps everything for the next one',
      () async {
    await server.down();
    await service.star(id: 'song1');
    await service.star(albumId: 'album1');

    await service.flushPendingStars();
    await server.up();
    await service.flushPendingStars();

    expect(server.calls, unorderedEquals(['star song1', 'star album1']));
  });

  // RD: a refusal from the server is treated like an outage and queued, so it is retried forever and the
  // user is never told it failed.
  test('a refusal from a reachable server is not queued', () async {
    server.refuse = true;

    await expectLater(service.star(id: 'song1'), throwsException);

    server.refuse = false;
    server.calls.clear();
    await service.flushPendingStars();
    expect(server.calls, isEmpty);
  });

  // RD: a 502 from the proxy while the server restarts is treated as a refusal, so the star is dropped for
  // good instead of being kept for when the server is back.
  test('a gateway error keeps the star for later', () async {
    server.httpStatus = 502;

    await service.star(id: 'song1');

    server.httpStatus = null;
    await service.flushPendingStars();
    expect(server.calls, ['star song1']);
  });

  // RD: a flush working from the list it read at the start sends a star after the user's later unstar of
  // the same item, and the item ends starred.
  test('an unstar made during a flush is not overwritten by it', () async {
    await server.down();
    await service.star(albumId: 'album1');
    await service.star(id: 'song1');
    await server.up();
    server.delay = const Duration(milliseconds: 200);

    final flushing = service.flushPendingStars();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await service.unstar(id: 'song1');
    await flushing;

    expect(server.calls.where((c) => c.endsWith('song1')).last, 'unstar song1');
  });
}
