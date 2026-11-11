import 'dart:convert';
import 'dart:io';

/// A Subsonic server holding one play queue, speaking the two index-based endpoints over real HTTP.
class FakeQueueServer {
  late HttpServer _server;
  final saves = <Map<String, List<String>>>[];
  bool failSaves = false;
  Map<String, dynamic>? queue;
  var _clock = 0;

  int get port => _server.port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  /// What another device's save leaves on the server.
  void saveFromOtherDevice(
      String client, List<String> ids, int index, int positionMs) {
    queue = {
      'entry': [
        for (final id in ids) {'id': id, 'title': 'T-$id'}
      ],
      'currentIndex': index,
      'position': positionMs,
      'changed': 'stamp-${++_clock}',
      'changedBy': client,
    };
  }

  Future<void> _handle(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    final params = <String, List<String>>{};
    void add(String query) {
      for (final pair in query.split('&').where((p) => p.isNotEmpty)) {
        final i = pair.indexOf('=');
        final key = Uri.decodeQueryComponent(pair.substring(0, i));
        params
            .putIfAbsent(key, () => [])
            .add(Uri.decodeQueryComponent(pair.substring(i + 1)));
      }
    }

    add(req.uri.query);
    add(body);
    Map<String, dynamic> response = {'status': 'ok'};
    if (req.uri.path.endsWith('/savePlayQueueByIndex')) {
      if (failSaves) {
        response = {
          'status': 'failed',
          'error': {'code': 0, 'message': 'down'}
        };
      } else {
        saves.add(params);
        final ids = params['id'] ?? [];
        saveFromOtherDevice(
            params['c']!.single,
            ids,
            int.parse(params['currentIndex']!.single),
            int.parse(params['position']!.single));
      }
    } else if (req.uri.path.endsWith('/getPlayQueueByIndex')) {
      response['playQueueByIndex'] = queue ?? {'username': 'u'};
    }
    req.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'subsonic-response': response}));
    await req.response.close();
  }
}
