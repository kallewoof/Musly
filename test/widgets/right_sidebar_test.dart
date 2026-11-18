import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musly/l10n/app_localizations.dart';
import 'package:musly/models/pick_reason.dart';
import 'package:musly/models/song.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/jukebox_service.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/services/transcoding_service.dart';
import 'package:musly/services/upnp_service.dart';
import 'package:musly/widgets/navigation/right_sidebar.dart';
import 'package:provider/provider.dart';

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

  static final song = Song(id: 's1', title: 'Song 1', artist: 'Artist A');

  @override
  Song? get currentSong => song;

  @override
  List<Song> get queue => [song];

  bool smart = true;
  double? tasteSet;

  @override
  bool get isSmartShuffle => smart;

  @override
  Future<void> setSmartShuffleTaste(double taste) async => tasteSet = taste;

  @override
  PickReason? get currentPickReason => const ShufflePick(
      completes: 2,
      skips: 0,
      starred: false,
      artistMean: null,
      draw: 0.9,
      typical: 0.6);
}

void main() {
  initializeTestEnvironment();

  // Built outside the tests' fake time, where the player's own timer would be left pending.
  late _Player player;
  setUp(() => player = _Player());

  // RD: the reasons are wired only into the phone's Now Playing, so on the desktop, where the playing song shows at
  // the top of the queue panel, nothing says why it was picked.
  testWidgets('the desktop queue panel shows why the playing song was picked',
      (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider<PlayerProvider>.value(
      value: player,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: SizedBox(width: 320, child: RightSidebar())),
      ),
    ));
    await tester.pump();

    expect(find.text('drew .90 (typical .60); the highest draws play'),
        findsOneWidget);
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(ChangeNotifierProvider<PlayerProvider>.value(
      value: player,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: SizedBox(width: 320, child: RightSidebar())),
      ),
    ));
    await tester.pump();
  }

  // RD: the slider is left out of the desktop panel, or shown when Smart Shuffle is off, where it does nothing; or
  // letting go of it does not reach the player.
  testWidgets('the desktop panel has the Smart Shuffle slider while it runs',
      (tester) async {
    player.smart = false;
    await pumpPanel(tester);
    expect(find.byKey(const ValueKey('smart-shuffle-taste')), findsNothing);

    player.smart = true;
    await pumpPanel(tester);
    await tester.drag(find.byType(Slider), const Offset(-300, 0));
    await tester.pump();

    expect(find.text('New to me'), findsOneWidget);
    expect(player.tasteSet, 0.0);
  });
}
