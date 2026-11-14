import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/song.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/jukebox_service.dart';
import 'package:musly/services/star_refresher.dart';
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
  int refreshes = 0;

  @override
  Song? get currentSong => song;

  @override
  Future<void> refreshCurrentStar() async => refreshes++;

  void show(Song? next) {
    song = next;
    notifyListeners();
  }
}

void main() {
  initializeTestEnvironment();

  late _Player player;

  setUp(() {
    player = _Player();
    StarRefresher(player).start();
  });

  tearDown(() => player.dispose());

  // RD: the star is checked only at launch, or on every position tick, so a later song shows the queue's stale heart, or the server is asked several times a second.
  test('asks once per new current song', () {
    player.show(Song(id: 'a', title: 'A'));
    player.show(Song(id: 'a', title: 'A'));
    player.show(Song(id: 'b', title: 'B'));

    expect(player.refreshes, 2);
  });

  // RD: a star made on another device while this app was in the background stays unseen until the song changes.
  test('asks again when the app returns to the foreground', () {
    player.show(Song(id: 'a', title: 'A'));
    final binding = TestWidgetsFlutterBinding.instance;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    expect(player.refreshes, 2);
  });
}
