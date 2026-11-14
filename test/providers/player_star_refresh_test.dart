import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/models.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/jukebox_service.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/services/transcoding_service.dart';
import 'package:musly/services/upnp_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bootstrap.dart';
import '../fake_queue_server.dart';
import '../test_helpers.dart';

/// A server whose answer about a song's star arrives when the test says so.
class _StarAnswers extends SubsonicService {
  final pending = <Completer<bool?>>[];

  @override
  Future<bool?> serverStarred(String id) {
    final c = Completer<bool?>();
    pending.add(c);
    return c.future;
  }
}

void main() {
  initializeTestEnvironment();

  late FakeQueueServer server;
  late _StarAnswers service;
  late PlayerProvider player;

  Song song(String id, {bool starred = false}) =>
      Song(id: id, title: 'T-$id', duration: 200, starred: starred);

  setUp(() async {
    server = FakeQueueServer();
    await server.start();
    SharedPreferences.setMockInitialValues({});
    await StorageService().init();
    service = _StarAnswers();
    await service.configure(ServerConfig(
        serverUrl: 'http://127.0.0.1:${server.port}',
        username: 'u',
        password: 'p'));
    player = PlayerProvider(
        service,
        StorageService(),
        FakeCastService(),
        UpnpService(),
        MuslyAudioHandler(),
        JukeboxService(),
        TranscodingService());
    player.queue.addAll([song('a'), song('b')]);
    await player.adoptTrackAt(0);
  });

  tearDown(() async {
    player.dispose();
    await server.stop();
  });

  // RD: the queue's stale copy wins over the server, so a song starred on the phone shows an empty heart on the desktop.
  test('takes the server\'s star for the current song', () async {
    final refresh = player.refreshCurrentStar();
    service.pending.single.complete(true);
    await refresh;

    expect(player.currentSong!.starred, isTrue);
  });

  // RD: the server's answer, asked before a tap, lands after it and undoes the tap.
  test('keeps a star changed here while the server was asked', () async {
    final refresh = player.refreshCurrentStar();
    await player.toggleFavorite();
    service.pending.single.complete(false);
    await refresh;

    expect(player.currentSong!.starred, isTrue);
  });

  // RD: the answer for a song already left is written onto the song now playing.
  test(
      'an answer for a song already left corrects that song, not the current one',
      () async {
    final refresh = player.refreshCurrentStar();
    await player.adoptTrackAt(1);
    service.pending.single.complete(true);
    await refresh;

    expect(player.currentSong!.id, 'b');
    expect(player.currentSong!.starred, isNot(isTrue));
    expect(player.queue.first.starred, isTrue);
  });

  // RD: a server that cannot answer reads as "not starred", so going offline clears every heart.
  test('leaves the star alone when the server cannot say', () async {
    await player.toggleFavorite();
    final refresh = player.refreshCurrentStar();
    service.pending.last.complete(null);
    await refresh;

    expect(player.currentSong!.starred, isTrue);
  });
}
