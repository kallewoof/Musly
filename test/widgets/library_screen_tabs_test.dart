import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musly/l10n/app_localizations.dart';
import 'package:musly/models/album.dart';
import 'package:musly/models/artist.dart';
import 'package:musly/models/server_config.dart';
import 'package:musly/models/song.dart';
import 'package:musly/providers/auth_provider.dart';
import 'package:musly/providers/library_provider.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/screens/main/library_screen.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/jukebox_service.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/services/transcoding_service.dart';
import 'package:musly/services/upnp_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../bootstrap.dart';
import '../test_helpers.dart';

class TestLibraryProvider extends LibraryProvider {
  final List<Album> _testAlbums;
  final List<Song> _testSongs;
  final List<Artist> _testArtists;
  bool _ensureLoadedCalled = false;

  TestLibraryProvider({
    required SubsonicService subsonicService,
    required MuslyAudioHandler audioHandler,
    List<Album> testAlbums = const [],
    List<Song> testSongs = const [],
    List<Artist> testArtists = const [],
  })  : _testAlbums = testAlbums,
        _testSongs = testSongs,
        _testArtists = testArtists,
        super(subsonicService, audioHandler);

  bool get ensureLoadedCalled => _ensureLoadedCalled;

  @override
  List<Album> get cachedAllAlbums => _testAlbums;

  @override
  List<Song> get cachedAllSongs => _testSongs;

  @override
  List<Artist> get artists => _testArtists;

  @override
  Future<void> ensureLibraryLoaded() async {
    _ensureLoadedCalled = true;
  }
}

void main() {
  initializeTestEnvironment();

  group('LibraryScreen Tabs & Content Tests', () {
    late SubsonicService subsonicService;
    late StorageService storageService;
    late PlayerProvider playerProvider;
    late AuthProvider authProvider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      subsonicService = SubsonicService();
      await subsonicService.configure(ServerConfig(
        serverUrl: 'https://demo.navidrome.org',
        username: 'user',
        password: 'password',
      ));
      storageService = StorageService();
      playerProvider = PlayerProvider(
        subsonicService,
        storageService,
        FakeCastService(),
        UpnpService(),
        MuslyAudioHandler(),
        JukeboxService(),
        TranscodingService(),
      );
      authProvider = AuthProvider(subsonicService, storageService);
    });

    testWidgets('Renders filter chips and triggers ensureLibraryLoaded when albums/songs empty',
        (tester) async {
      final libraryProvider = TestLibraryProvider(
        subsonicService: subsonicService,
        audioHandler: MuslyAudioHandler(),
        testAlbums: [],
        testSongs: [],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<SubsonicService>.value(value: subsonicService),
            Provider<StorageService>.value(value: storageService),
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<PlayerProvider>.value(value: playerProvider),
            ChangeNotifierProvider<LibraryProvider>.value(value: libraryProvider),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LibraryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify filter chips exist
      final albumsChip = find.ancestor(
        of: find.text('Albums'),
        matching: find.byType(AnimatedContainer),
      );
      final songsChip = find.ancestor(
        of: find.text('Songs'),
        matching: find.byType(AnimatedContainer),
      );
      final artistsChip = find.ancestor(
        of: find.text('Artists'),
        matching: find.byType(AnimatedContainer),
      );

      expect(albumsChip, findsOneWidget);
      expect(songsChip, findsOneWidget);
      expect(artistsChip, findsOneWidget);

      // Verify ensureLibraryLoaded was called on initial load because albums/songs are empty
      expect(libraryProvider.ensureLoadedCalled, isTrue);

      // Tap on Albums tab
      await tester.tap(albumsChip);
      await tester.pumpAndSettle();

      // Empty albums should show "No albums found", NOT "No songs found"
      expect(find.text('No albums found'), findsOneWidget);
    });

    testWidgets('Populates albums and songs when selecting their respective tabs',
        (tester) async {
      final testAlbums = [
        Album(id: 'alb_1', name: 'Random Access Memories', artist: 'Daft Punk'),
        Album(id: 'alb_2', name: 'Discovery', artist: 'Daft Punk'),
      ];
      final testSongs = [
        Song(id: 'song_1', title: 'Get Lucky', artist: 'Daft Punk', album: 'Random Access Memories'),
        Song(id: 'song_2', title: 'One More Time', artist: 'Daft Punk', album: 'Discovery'),
      ];

      final libraryProvider = TestLibraryProvider(
        subsonicService: subsonicService,
        audioHandler: MuslyAudioHandler(),
        testAlbums: testAlbums,
        testSongs: testSongs,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<SubsonicService>.value(value: subsonicService),
            Provider<StorageService>.value(value: storageService),
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<PlayerProvider>.value(value: playerProvider),
            ChangeNotifierProvider<LibraryProvider>.value(value: libraryProvider),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LibraryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final albumsChip = find.ancestor(
        of: find.text('Albums'),
        matching: find.byType(AnimatedContainer),
      );
      final songsChip = find.ancestor(
        of: find.text('Songs'),
        matching: find.byType(AnimatedContainer),
      );

      // Tap on Albums tab
      await tester.tap(albumsChip);
      await tester.pumpAndSettle();

      // Albums should be visible
      expect(find.text('Random Access Memories'), findsOneWidget);
      expect(find.text('Discovery'), findsOneWidget);

      // Tap on Songs tab (ensure visible in horizontal scroll)
      await tester.ensureVisible(songsChip);
      await tester.pumpAndSettle();
      await tester.tap(songsChip);
      await tester.pumpAndSettle();

      // Songs should be visible
      expect(find.text('Get Lucky'), findsOneWidget);
      expect(find.text('One More Time'), findsOneWidget);
    });

    // RD: the Songs view's Shuffle is wired to the shuffle toggle, so pressing it shuffles whatever was
    // already queued instead of playing the whole library.
    testWidgets('Shuffle on the Songs view shuffles the whole library',
        (tester) async {
      final libraryProvider = TestLibraryProvider(
        subsonicService: subsonicService,
        audioHandler: MuslyAudioHandler(),
        testSongs: [
          for (var i = 0; i < 5; i++)
            Song(id: 's$i', title: 'Song $i', artist: 'Artist'),
        ],
      );
      final player = _ShuffleRecordingPlayer(subsonicService, storageService);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<SubsonicService>.value(value: subsonicService),
            Provider<StorageService>.value(value: storageService),
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<PlayerProvider>.value(value: player),
            ChangeNotifierProvider<LibraryProvider>.value(
                value: libraryProvider),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LibraryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.ancestor(
        of: find.text('Songs'),
        matching: find.byType(AnimatedContainer),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Shuffle'));
      await tester.pump();

      expect(player.libraryShuffles, 1);
      expect(player.shuffleEnabled, isFalse);

      // Made inside the test, so its periodic sync timer runs on the fake clock and must be stopped.
      await tester.pumpWidget(const SizedBox());
      player.dispose();
    });
  });
}

/// Records the library shuffle instead of playing: starting playback reaches the network.
class _ShuffleRecordingPlayer extends PlayerProvider {
  _ShuffleRecordingPlayer(SubsonicService subsonic, StorageService storage)
      : super(subsonic, storage, FakeCastService(), UpnpService(),
            MuslyAudioHandler(), JukeboxService(), TranscodingService());

  int libraryShuffles = 0;

  @override
  Future<void> shuffleLibrary() async => libraryShuffles++;
}
