import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:musly/models/song.dart';
import 'package:musly/models/server_config.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/providers/library_provider.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/upnp_service.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/jukebox_service.dart';
import 'package:musly/services/transcoding_service.dart';
import 'package:musly/services/tv_detection_service.dart';
import 'package:musly/widgets/navigation/desktop_player_bar.dart';
import 'package:musly/widgets/modals/song_options_modal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test_helpers.dart';
import '../bootstrap.dart';

/// The song menu asks the server whether it keeps tag edits; this server is never reached in tests, and its
/// request would outlive the test.
class _NoTagOverlayService extends SubsonicService {
  @override
  Future<bool> supportsTagOverlay() async => false;
}

/// A player whose shuffle button state the test sets, counting the button's taps.
class _ShufflePlayer extends PlayerProvider {
  _ShufflePlayer(SubsonicService s)
      : super(s, StorageService(), FakeCastService(), UpnpService(),
            MuslyAudioHandler(), JukeboxService(), TranscodingService());

  ShuffleState state = ShuffleState.off;
  int cycles = 0;

  @override
  ShuffleState get shuffleState => state;

  @override
  Future<void> cycleShuffle() async {
    cycles++;
    state = ShuffleState.values[(state.index + 1) % ShuffleState.values.length];
    notifyListeners();
  }
}

void main() {
  initializeTestEnvironment();

  group('DesktopPlayerBar Actions Tests', () {
    late SubsonicService subsonicService;
    late PlayerProvider playerProvider;
    late LibraryProvider libraryProvider;
    // Built here, outside the tests' fake time, where the player's own timer would be left pending.
    late _ShufflePlayer shufflePlayer;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      subsonicService = _NoTagOverlayService();
      await subsonicService.configure(ServerConfig(
        serverUrl: 'https://demo.navidrome.org',
        username: 'user',
        password: 'password',
      ));
      final storageService = StorageService();
      playerProvider = PlayerProvider(
        subsonicService,
        storageService,
        FakeCastService(),
        UpnpService(),
        MuslyAudioHandler(),
        JukeboxService(),
        TranscodingService(),
      );
      libraryProvider = LibraryProvider(
        subsonicService,
        MuslyAudioHandler(),
      );
      shufflePlayer = _ShufflePlayer(subsonicService);
    });

    tearDownAll(() {
      TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
          .resetPhysicalSize();
      TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
          .resetDevicePixelRatio();
    });

    testWidgets(
        'renders favorite, add to playlist, and more options buttons for current song',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;

      final song = Song(
        id: 'test_song_1',
        title: 'Test Song Title',
        artist: 'Test Artist',
        duration: 210,
      );

      libraryProvider.setServerOfflineMode(true);
      playerProvider.playSong(song);

      await tester.pumpWidget(
        createTestApp(
          playerProvider: playerProvider,
          libraryProvider: libraryProvider,
          subsonicService: subsonicService,
          child: ChangeNotifierProvider<TvDetectionService>.value(
            // A singleton: a provider that created it would dispose it for the tests after this one.
            value: TvDetectionService(),
            child: const SizedBox(
              height: 90,
              child: DesktopPlayerBar(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(DesktopPlayerBar), findsOneWidget);
      expect(find.text('Test Song Title'), findsOneWidget);
      expect(find.text('Test Artist'), findsOneWidget);

      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.byIcon(Icons.playlist_add_rounded), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();

      expect(find.byType(SongOptionsModal), findsOneWidget);
      expect(find.text('Add to Playlist'), findsOneWidget);

      Navigator.pop(tester.element(find.byType(SongOptionsModal)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.playlist_add_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Add to Playlist'), findsWidgets);
    });

    // RD: the desktop bar keeps the two-state shuffle button: it shows Smart Shuffle as plain shuffle, and a tap
    // toggles plain shuffle instead of stepping to the next state.
    testWidgets('steps the shuffle button through its states, showing Smart Shuffle',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      final player = shufflePlayer;
      libraryProvider.setServerOfflineMode(true);
      player.playSong(Song(id: 's1', title: 'Song 1', duration: 210));

      await tester.pumpWidget(createTestApp(
        playerProvider: player,
        libraryProvider: libraryProvider,
        subsonicService: subsonicService,
        child: ChangeNotifierProvider<TvDetectionService>.value(
          value: TvDetectionService(),
          child: const SizedBox(height: 90, child: DesktopPlayerBar()),
        ),
      ));
      await tester.pump(const Duration(seconds: 1));
      IconData icon() => tester
          .widget<Icon>(find.descendant(
              of: find.byKey(const ValueKey('shuffle-button')),
              matching: find.byType(Icon)))
          .icon!;

      expect(icon(), Icons.shuffle_rounded);
      await tester.tap(find.byKey(const ValueKey('shuffle-button')));
      await tester.tap(find.byKey(const ValueKey('shuffle-button')));
      await tester.pump();

      expect(player.cycles, 2);
      expect(icon(), Icons.auto_awesome_rounded);

      // playSong leaves a 1.2 s timer of its own.
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
