import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/screens/settings/settings_playback_tab.dart';
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

  int refreshes = 0;

  @override
  Future<void> refreshReplayGain() async => refreshes++;
}

void main() {
  initializeTestEnvironment();

  // Built outside the tests' fake time, where the player's own timer would be left pending.
  late _Player player;
  setUp(() {
    SharedPreferences.setMockInitialValues({'replay_gain_mode': 1});
    player = _Player();
  });

  // RD: the settings are saved but the playing song keeps its old gain until the next one, so turning
  // normalization off or changing its mode seems to do nothing.
  testWidgets('a normalization change applies to the playing song at once',
      (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(createTestApp(
        playerProvider: player, child: const SettingsPlaybackTab()));
    await tester.pumpAndSettle();

    await tester.tap(
        find.byWidgetPredicate((w) => w is DropdownButton<ReplayGainMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Album').last);
    await tester.pumpAndSettle();
    expect(player.refreshes, 1);

    await tester.tap(find.text('Prevent Clipping'));
    await tester.pumpAndSettle();
    expect(player.refreshes, 2, reason: 'prevent clipping');

    // The pre-amp slider, then the fallback gain slider (the last on the screen).
    final sliders = find.byType(Slider);
    await tester.drag(
        sliders.at(sliders.evaluate().length - 2), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(player.refreshes, greaterThan(2), reason: 'pre-amp');
    final afterPreamp = player.refreshes;
    await tester.drag(sliders.last, const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(player.refreshes, greaterThan(afterPreamp), reason: 'fallback gain');
  });
}
