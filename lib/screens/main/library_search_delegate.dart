import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:musly/providers/library_provider.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/theme/app_theme.dart';
import 'package:musly/utils/navigation_helper.dart';
import 'package:musly/screens/detail/album_screen.dart';
import 'package:musly/screens/detail/artist_screen.dart';
import 'package:musly/screens/detail/playlist_screen.dart';
import 'package:musly/widgets/common/album_artwork.dart';
import 'package:musly/widgets/common/song_tile.dart';
import 'package:musly/l10n/app_localizations.dart';

class LibrarySearchDelegate extends SearchDelegate<String> {
  final LibraryProvider libraryProvider;
  final bool isDark;

  LibrarySearchDelegate({required this.libraryProvider, required this.isDark})
      : super(
          searchFieldLabel: 'Search in Library...',
          searchFieldStyle: TextStyle(
            color: isDark ? Colors.white : Colors.black,
          ),
        );

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppTheme.darkBackground : Colors.white,
        elevation: 0.5,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
      ),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, ''),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.search,
              size: 64,
              color: isDark ? Colors.white38 : Colors.black26,
            ),
            const SizedBox(height: 16),
            Text(
              'Search your library',
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black45,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }
    return _buildSearchResults(context);
  }

  Widget _buildSearchResults(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final lowerQuery = query.toLowerCase();
    final cached = libraryProvider.searchCached(query);
    final songs = cached.songs;
    final artists = cached.artists;
    final albums = cached.albums;
    final playlists = libraryProvider.playlists
        .where((p) => p.name.toLowerCase().contains(lowerQuery))
        .toList();

    if (songs.isEmpty &&
        artists.isEmpty &&
        albums.isEmpty &&
        playlists.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.search,
              size: 64,
              color: isDark ? Colors.white38 : Colors.black26,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.noResults,
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black45,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    void open(Widget screen) {
      close(context, '');
      NavigationHelper.push(context, screen);
    }

    return ListView(
      children: [
        if (songs.isNotEmpty) ...[
          _sectionHeader(l10n.songs),
          ...songs.map(
            (song) => SongTile(
              song: song,
              onTap: () {
                final player =
                    Provider.of<PlayerProvider>(context, listen: false);
                close(context, '');
                player.playSongWithRadio(song);
              },
            ),
          ),
        ],
        if (artists.isNotEmpty) ...[
          _sectionHeader(l10n.artists),
          ...artists.map(
            (artist) => ListTile(
              leading: AlbumArtwork(
                coverArt: artist.coverArt ??
                    artist.artistImageUrl ??
                    (artist.id.isNotEmpty ? 'ar-${artist.id}' : null),
                size: 48,
                borderRadius: 24,
              ),
              title: Text(artist.name),
              subtitle: artist.albumCount == null
                  ? null
                  : Text(l10n.albumsCount(artist.albumCount!)),
              onTap: () => open(ArtistScreen(artistId: artist.id)),
            ),
          ),
        ],
        if (albums.isNotEmpty) ...[
          _sectionHeader(l10n.albums),
          ...albums.map(
            (album) => ListTile(
              leading: AlbumArtwork(
                coverArt: album.coverArt,
                size: 48,
                borderRadius: 4,
              ),
              title: Text(album.name),
              subtitle: album.artist == null ? null : Text(album.artist!),
              onTap: () => open(AlbumScreen(albumId: album.id)),
            ),
          ),
        ],
        if (playlists.isNotEmpty) ...[
          _sectionHeader(l10n.playlists),
          ...playlists.map(
            (playlist) => ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: AppTheme.brandRed.withValues(alpha: 0.2),
                ),
                child: const Icon(
                  CupertinoIcons.music_note_list,
                  color: AppTheme.brandRed,
                ),
              ),
              title: Text(playlist.name),
              subtitle: Text(l10n.songsCount(playlist.songCount ?? 0)),
              onTap: () => open(
                PlaylistScreen(
                  playlistId: playlist.id,
                  playlistName: playlist.name,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
    );
  }
}
