import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/song.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/favorite_control_service.dart';
import 'package:musly/services/jukebox_service.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/services/transcoding_service.dart';
import 'package:musly/services/upnp_service.dart';

import '../bootstrap.dart';
import '../test_helpers.dart';

class _Player extends PlayerProvider {
  _Player()
      : super(
            SubsonicService(),
            StorageService(),
            FakeCastService(),
            UpnpService(),
            MuslyAudioHandler(),
            JukeboxService(),
            TranscodingService());

  Song? song;
  int toggles = 0;

  @override
  Song? get currentSong => song;

  @override
  Future<void> toggleFavorite() async => toggles++;

  void show(Song? next) {
    song = next;
    notifyListeners();
  }
}

void main() {
  initializeTestEnvironment();

  const channel = MethodChannel('test/favorite_control');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _Player player;
  late List<bool> sent;

  setUp(() {
    player = _Player();
    sent = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setState') {
        sent.add(call.arguments['starred'] as bool);
      }
      return null;
    });
    FavoriteControlService(player, channel: channel).start();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    player.dispose();
  });

  // RD: the control is told only when the song changes, so starring the playing song in the app leaves the
  // lock screen showing an empty star, and the next press there unstars it again.
  test('tells the control when the current song is starred or unstarred',
      () async {
    final song = Song(id: 's1', title: 'Track');
    player.show(song);
    player.show(song.copyWith(starred: true));
    player.show(song.copyWith(starred: false));
    await pumpEventQueue();

    expect(sent, [false, true, false]);
  });

  // RD: the control is told only when the star changes, so moving from a starred song to an unstarred one
  // leaves the lock screen showing a filled star for the new song.
  test('tells the control the star state of each new song', () async {
    player.show(Song(id: 's1', title: 'A', starred: true));
    player.show(Song(id: 's2', title: 'B'));
    player.show(null);
    await pumpEventQueue();

    expect(sent, [false, true, false]);
  });

  // RD: the change check is dropped, so every position tick (several a second while playing) crosses the
  // platform channel and reloads the lock-screen control.
  test('stays quiet while nothing the control shows changes', () async {
    final song = Song(id: 's1', title: 'Track', starred: true);
    player.show(song);
    for (var i = 0; i < 5; i++) {
      player.show(song);
    }
    await pumpEventQueue();

    expect(sent, [false, true]);
  });

  // RD: the press from the lock screen reaches Dart but is not wired to the player, so the control does
  // nothing and the star never changes.
  test('a press on the control toggles the current song', () async {
    await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('toggle')),
        (_) {});

    expect(player.toggles, 1);
  });
}
