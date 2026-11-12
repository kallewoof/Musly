import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/jukebox_service.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/services/transcoding_service.dart';
import 'package:musly/services/upnp_service.dart';
import 'package:musly/widgets/now_playing/volume_slider.dart';
import 'package:provider/provider.dart';

import '../bootstrap.dart';
import '../test_helpers.dart';

void main() {
  initializeTestEnvironment();

  const methods = MethodChannel('com.kurenai7968.volume_controller.method');
  const events =
      MethodChannel('com.kurenai7968.volume_controller.volume_listener_event');

  /// Shows the slider on [platform] and returns whether it subscribed to volume_controller's listener.
  Future<bool> listensOn(WidgetTester tester, TargetPlatform platform) async {
    var listened = false;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        methods, (call) async => call.method == 'getVolume' ? 0.5 : null);
    messenger.setMockMethodCallHandler(events, (call) async {
      if (call.method == 'listen') listened = true;
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(methods, null);
      messenger.setMockMethodCallHandler(events, null);
    });

    final player = PlayerProvider(
        SubsonicService(),
        StorageService(),
        FakeCastService(),
        UpnpService(),
        MuslyAudioHandler(),
        JukeboxService(),
        TranscodingService());
    debugDefaultTargetPlatformOverride = platform;
    try {
      await tester.pumpWidget(ChangeNotifierProvider<PlayerProvider>.value(
        value: player,
        child: const MaterialApp(home: Scaffold(body: VolumeSlider())),
      ));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    player.dispose();
    return listened;
  }

  // RD: the slider follows the system volume on iOS too, and volume_controller makes the audio session
  // mixable to do it, so opening Now Playing takes Musly off the lock screen and the AirPods start Apple
  // Music on top of it.
  testWidgets('the slider does not listen for volume changes on iOS',
      (tester) async {
    expect(await listensOn(tester, TargetPlatform.android), isTrue,
        reason: 'the listener is detected where it is wanted');
    expect(await listensOn(tester, TargetPlatform.iOS), isFalse);
  });
}
