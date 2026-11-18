import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musly/models/song.dart';
import 'package:musly/providers/library_provider.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/screens/main/search_screen.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/jukebox_service.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/services/transcoding_service.dart';
import 'package:musly/services/upnp_service.dart';

import '../bootstrap.dart';
import '../test_helpers.dart';

class _Library extends LibraryProvider {
  _Library() : super(SubsonicService(), MuslyAudioHandler());

  @override
  Future<SearchResult> search(String query) async => SearchResult(
      artists: const [],
      albums: const [],
      songs: [Song(id: 's1', title: 'Song 1', artist: 'Artist A')]);
}

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

  @override
  Future<void> playSongWithRadio(Song song) async {}
}

/// Which queries the search screen keeps as recent searches.
void main() {
  initializeTestEnvironment();

  // Built outside the tests' fake time, where the player's own timer would be left pending.
  late _Player player;
  setUp(() => player = _Player());

  Future<void> pumpSearch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(createTestApp(
        playerProvider: player,
        libraryProvider: _Library(),
        child: const SearchScreen()));
    await tester.pump();
  }

  /// Types [text] a letter at a time, pausing past the live search's delay after each.
  Future<void> typeSlowly(WidgetTester tester, String text) async {
    for (var i = 1; i <= text.length; i++) {
      await tester.enterText(find.byType(TextField), text.substring(0, i));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  /// The recent searches, shown once the field is emptied.
  Future<List<String>> recent(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 300));
    return [
      for (final chip in tester.widgetList<InputChip>(find.byType(InputChip)))
        (chip.label as Text).data!
    ];
  }

  // RD: every live search is kept, so typing a word leaves each of its prefixes behind as a recent search.
  testWidgets('typing keeps no recent searches', (tester) async {
    await pumpSearch(tester);

    await typeSlowly(tester, 'pålso');

    expect(await recent(tester), isEmpty);
  });

  // RD: a submitted query is not kept, or kept with the prefixes typed on the way to it.
  testWidgets('a submitted query is kept, whole', (tester) async {
    await pumpSearch(tester);

    await typeSlowly(tester, 'pålso');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 300));

    expect(await recent(tester), ['pålso']);
  });

  // RD: a query is kept only when submitted, so one whose result was simply tapped is forgotten.
  testWidgets('playing a result keeps its query', (tester) async {
    await pumpSearch(tester);

    await typeSlowly(tester, 'song');
    await tester.tap(find.text('Song 1').last);
    await tester.pump(const Duration(milliseconds: 300));

    expect(await recent(tester), ['song']);
  });
}
