import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/server_config.dart';
import 'package:musly/services/subsonic_service.dart';

import '../bootstrap.dart';
import '../fake_queue_server.dart';

/// The tag overlay requests as they reach the server (navidrome's unimouseTagOverlay endpoints).
void main() {
  initializeTestEnvironment();

  late FakeQueueServer server;
  late SubsonicService service;

  setUp(() async {
    server = FakeQueueServer();
    await server.start();
    service = SubsonicService();
    await service.configure(ServerConfig(
        serverUrl: 'http://127.0.0.1:${server.port}',
        username: 'u',
        password: 'p'));
  });

  tearDown(() => server.stop());

  // RD: a field the user did not change goes out as an empty parameter, which the server reads as "clear this
  // tag", so fixing a title wipes the song's artist; or an emptied field is left out and can never clear a tag.
  test(
      'sends the fields given, an empty one as empty, and leaves the others out',
      () async {
    await service.setTagOverlay('s1', title: 'Song 1', composer: '');

    final params = server.lastParams['setTagOverlay']!;
    expect(params['id'], ['s1']);
    expect(params['title'], ['Song 1']);
    expect(params['composer'], ['']);
    expect(params.containsKey('artist'), isFalse);
    expect(params.containsKey('album'), isFalse);
  });

  // RD: the composers are read from the wrong part of the song (or other roles count as composers), so the editor
  // opens with an empty or wrong composer.
  test('reads the composers from the song\'s contributors', () async {
    server.song = {
      'id': 's1',
      'title': 'Song 1',
      'contributors': [
        {
          'role': 'composer',
          'artist': {'id': 'a1', 'name': 'Composer A'}
        },
        {
          'role': 'performer',
          'subRole': 'Vocals',
          'artist': {'id': 'a2', 'name': 'Voice A'}
        },
        {
          'role': 'composer',
          'artist': {'id': 'a3', 'name': 'Composer B'}
        },
      ],
    };

    final now = await service.getSongWithComposers('s1');

    expect(now.song.title, 'Song 1');
    expect(now.composers, ['Composer A', 'Composer B']);
  });

  // RD: the app looks for another extension name than the server advertises, so "Edit tags" never shows on our
  // server, or shows on servers that cannot keep an edit.
  test('finds the tag overlay only on a server that advertises it', () async {
    expect(await service.supportsTagOverlay(), isFalse);

    server.tagOverlay = true;
    final ours = SubsonicService();
    await ours.configure(ServerConfig(
        serverUrl: 'http://127.0.0.1:${server.port}',
        username: 'u',
        password: 'p'));
    expect(await ours.supportsTagOverlay(), isTrue);
  });
}
