import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/album.dart';
import 'package:musly/models/song.dart';
import 'package:musly/providers/library_provider.dart';
import 'package:musly/screens/main/home_screen.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/recommendation_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:provider/provider.dart';

import '../bootstrap.dart';
import '../test_helpers.dart';

class _Library extends LibraryProvider {
  _Library(this.recent) : super(SubsonicService(), MuslyAudioHandler());

  final List<Album> recent;

  @override
  List<Album> get recentAlbums => recent;

  @override
  bool get isInitialized => true;
}

void main() {
  initializeTestEnvironment();

  // RD: songs without an album tag, which the server lists per artist as "[Unknown Album]", fill the quick tiles
  // and Jump back in with untitled, coverless cards that crowd out the albums the user played.
  testWidgets('Home shows recently played albums, not songs without one',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final library = _Library([
      Album(id: 'u1', name: Song.unknownAlbum, artist: 'Artist A'),
      Album(id: 'a1', name: 'Album 1', artist: 'Artist B'),
      Album(id: 'u2', name: Song.unknownAlbum, artist: 'Artist C'),
    ]);

    await tester.pumpWidget(ChangeNotifierProvider<RecommendationService>.value(
      value: RecommendationService(),
      child: createTestApp(libraryProvider: library, child: const HomeScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Album 1'), findsWidgets);
    expect(find.text(Song.unknownAlbum), findsNothing);
  });
}
