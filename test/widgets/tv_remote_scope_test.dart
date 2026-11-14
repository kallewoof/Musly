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
import 'package:musly/widgets/navigation/tv_remote_scope.dart';
import 'package:provider/provider.dart';

import '../bootstrap.dart';
import '../test_helpers.dart';

class _TogglePlayer extends PlayerProvider {
  _TogglePlayer()
      : super(
            SubsonicService(),
            StorageService(),
            FakeCastService(),
            UpnpService(),
            MuslyAudioHandler(),
            JukeboxService(),
            TranscodingService());

  int toggles = 0;

  @override
  Future<void> togglePlayPause() async => toggles++;
}

void main() {
  initializeTestEnvironment();

  late _TogglePlayer player;

  setUp(() => player = _TogglePlayer());

  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(ChangeNotifierProvider<PlayerProvider>.value(
        value: player,
        child: MaterialApp(
          home: TvRemoteScope(child: Scaffold(body: child)),
        ),
      ));

  // RD: the space shortcut swallows the key whatever has focus, so typing a space in the search field toggles
  // playback and the space never reaches the text.
  testWidgets('leaves space to a focused text field', (tester) async {
    await pump(tester, const TextField(autofocus: true));
    await tester.pump();

    final handled = await tester.sendKeyEvent(LogicalKeyboardKey.space);

    expect(handled, isFalse, reason: 'the key must go on to the text field');
    expect(player.toggles, 0);
  });

  // RD: the text-field guard is widened to anything focusable, so space stops toggling playback anywhere.
  testWidgets('toggles playback on space when no text field has focus',
      (tester) async {
    await pump(tester, Focus(autofocus: true, child: const SizedBox()));
    await tester.pump();

    final handled = await tester.sendKeyEvent(LogicalKeyboardKey.space);

    expect(handled, isTrue);
    expect(player.toggles, 1);
  });
}
