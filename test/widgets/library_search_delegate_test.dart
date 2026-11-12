import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musly/l10n/app_localizations.dart';
import 'package:musly/models/album.dart';
import 'package:musly/models/artist.dart';
import 'package:musly/models/playlist.dart';
import 'package:musly/models/server_config.dart';
import 'package:musly/models/song.dart';
import 'package:musly/providers/library_provider.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/screens/main/library_search_delegate.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/jukebox_service.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/services/transcoding_service.dart';
import 'package:musly/services/upnp_service.dart';
import 'package:musly/widgets/common/song_tile.dart';
import 'package:provider/provider.dart';

import '../bootstrap.dart';
import '../test_helpers.dart';

/// The library as the Library screen holds it: what the public getters return, which is also where merged
/// local files appear.
class _CachedLibrary extends LibraryProvider {
  _CachedLibrary(SubsonicService subsonic)
      : super(subsonic, MuslyAudioHandler());

  @override
  List<Song> get cachedAllSongs => [
        Song(
            id: 's1',
            title: 'Song 1',
            artist: 'Artist A',
            album: 'Album 1'),
        Song(
            id: 's2',
            title: 'Quiet Song',
            artist: 'Artist B',
            album: 'Album 3'),
      ];

  @override
  List<Artist> get artists => [
        Artist(id: 'ar1', name: 'Artist A'),
        Artist(id: 'ar2', name: 'Artist B'),
      ];

  @override
  List<Album> get cachedAllAlbums => [
        Album(id: 'al1', name: 'Album 2', artist: 'Artist A'),
        Album(
            id: 'al2',
            name: 'Album 3',
            artist: 'Artist B'),
      ];

  @override
  List<Playlist> get playlists => [
        Playlist(id: 'p1', name: 'Artist A marathon'),
        Playlist(id: 'p2', name: 'Evening mix'),
      ];
}

class _RadioRecordingPlayer extends PlayerProvider {
  _RadioRecordingPlayer(SubsonicService subsonic)
      : super(subsonic, StorageService(), FakeCastService(), UpnpService(),
            MuslyAudioHandler(), JukeboxService(), TranscodingService());

  final List<String> radioSeeds = [];

  @override
  Future<void> playSongWithRadio(Song song) async => radioSeeds.add(song.id);
}

void main() {
  initializeTestEnvironment();

  late SubsonicService subsonic;
  late _RadioRecordingPlayer player;

  setUp(() async {
    subsonic = SubsonicService();
    await subsonic.configure(ServerConfig(
        serverUrl: 'https://demo.navidrome.org',
        username: 'user',
        password: 'password'));
    player = _RadioRecordingPlayer(subsonic);
  });

  Future<void> search(WidgetTester tester, String query) async {
    final library = _CachedLibrary(subsonic);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<SubsonicService>.value(value: subsonic),
        ChangeNotifierProvider<PlayerProvider>.value(value: player),
        ChangeNotifierProvider<LibraryProvider>.value(value: library),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSearch(
                context: context,
                delegate: LibrarySearchDelegate(
                    libraryProvider: library, isDark: false)),
            child: const Text('open search'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), query);
    await tester.pumpAndSettle();
  }

  Finder row(String title) => find.byWidgetPredicate((w) =>
      w is ListTile && w.title is Text && (w.title as Text).data == title);

  // RD: the Library search goes back to matching playlist names only (or reads the private caches, which miss
  // merged local files), so searching for an artist the library holds shows "No results".
  testWidgets(
      'finds songs, artists, albums and playlists in the cached library',
      (tester) async {
    await search(tester, 'artist a');

    expect(find.widgetWithText(SongTile, 'Song 1'), findsOneWidget);
    expect(row('Artist A'), findsOneWidget);
    expect(row('Album 2'), findsOneWidget);
    expect(row('Artist A marathon'), findsOneWidget);

    expect(find.text('Quiet Song'), findsNothing);
    expect(find.text('Artist B'), findsNothing);
    expect(find.text('Album 3'), findsNothing);
    expect(find.text('Evening mix'), findsNothing);
  });

  // RD: the song row falls back to SongTile's own tap, which plays that one song and stops, instead of
  // starting a radio from it as the Search tab does.
  testWidgets('tapping a song closes the search and starts a radio from it',
      (tester) async {
    await search(tester, 'quiet');

    await tester.tap(find.widgetWithText(SongTile, 'Quiet Song'));
    await tester.pumpAndSettle();

    expect(player.radioSeeds, ['s2']);
    expect(find.byType(TextField), findsNothing);
  });
}
