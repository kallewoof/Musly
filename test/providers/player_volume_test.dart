import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/song.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/jukebox_service.dart';
import 'package:musly/services/replay_gain_service.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/services/transcoding_service.dart';
import 'package:musly/services/upnp_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bootstrap.dart';
import '../test_helpers.dart';

/// The volume the player is given for a song, which must come out as the ReplayGain gain asked for.
void main() {
  initializeTestEnvironment();

  late PlayerProvider player;
  final cubic = PlayerProvider.volumeIsCubic;

  setUp(() async {
    // Normalization by track, the slider at full.
    SharedPreferences.setMockInitialValues({'replay_gain_mode': 1});
    await ReplayGainService().initialize();
    player = PlayerProvider(
        SubsonicService(),
        StorageService(),
        FakeCastService(),
        UpnpService(),
        MuslyAudioHandler(),
        JukeboxService(),
        TranscodingService());
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  tearDown(() {
    PlayerProvider.volumeIsCubic = cubic;
    player.dispose();
  });

  /// The gain in dB that a volume comes out as, on a backend that cubes it or one that does not.
  double gainDb(double volume, {required bool cubic}) =>
      20 * log(cubic ? pow(volume, 3) : volume) / ln10;

  // RD: the ReplayGain factor goes to mpv as is, which cubes it, so -6 dB comes out as -18 and normalized songs
  // play far too quietly on Linux; or the cube root is applied where the backend is linear, making them too loud.
  test(
      'a song comes out at its ReplayGain gain, on a cubic backend or a linear one',
      () {
    final tagged = Song(id: 'a', title: 'A', replayGainTrackGain: -6);
    final untagged =
        Song(id: 'b', title: 'B'); // the fallback gain, -6 dB by default

    for (final isCubic in [true, false]) {
      PlayerProvider.volumeIsCubic = isCubic;
      for (final song in [tagged, untagged]) {
        expect(gainDb(player.getEffectiveVolumeForSong(song), cubic: isCubic),
            closeTo(-6, 0.01),
            reason: '${song.id}, cubic: $isCubic');
      }
    }
  });
}
