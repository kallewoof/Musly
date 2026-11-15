import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musly/l10n/app_localizations.dart';
import 'package:musly/models/song.dart';
import 'package:musly/providers/library_provider.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/services/audio_handler.dart';
import 'package:musly/services/jukebox_service.dart';
import 'package:musly/services/storage_service.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/services/tag_edit_service.dart';
import 'package:musly/services/transcoding_service.dart';
import 'package:musly/services/upnp_service.dart';
import 'package:musly/widgets/modals/edit_tags_sheet.dart';
import 'package:provider/provider.dart';

import '../bootstrap.dart';
import '../test_helpers.dart';

class _Server extends SubsonicService {
  _Server(this.supported);
  final bool supported;
  @override
  Future<bool> supportsTagOverlay() async => supported;
}

class _Service extends TagEditService {
  _Service(super.s, super.l, super.p, {required this.edited});
  final bool edited;
  Object? failure;
  final saves = <TagFields>[];
  int resets = 0;
  static const shown = (title: 'song_1', artist: '', composer: '', album: '');

  @override
  Future<({TagFields fields, bool edited})> load(String id) async =>
      (fields: shown, edited: edited);

  @override
  Future<Song?> save(String id, TagFields initial, TagFields edited) async {
    if (failure != null) throw failure!;
    saves.add(edited);
    return Song(id: id, title: edited.title);
  }

  @override
  Future<Song?> reset(String id, TagFields before) async {
    resets++;
    return Song(id: id, title: 'song_1');
  }
}

void main() {
  initializeTestEnvironment();

  final song = Song(id: 's1', title: 'song_1');
  late SubsonicService subsonic;
  late LibraryProvider library;
  late PlayerProvider player;

  // Built outside the tests' fake time, where the player's own timer would be left pending.
  setUp(() {
    subsonic = SubsonicService();
    library = LibraryProvider(subsonic, MuslyAudioHandler());
    player = PlayerProvider(
        subsonic,
        StorageService(),
        FakeCastService(),
        UpnpService(),
        MuslyAudioHandler(),
        JukeboxService(),
        TranscodingService());
  });

  Widget app(Widget child, {SubsonicService? server}) => MultiProvider(
        providers: [Provider<SubsonicService>.value(value: server ?? subsonic)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      );

  Future<_Service> openSheet(WidgetTester tester, {bool edited = false}) async {
    final service = _Service(subsonic, library, player, edited: edited);
    // A fresh tree, so a sheet left open by an earlier step is gone.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(Builder(
      builder: (context) => TextButton(
        onPressed: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => EditTagsSheet(song: song, service: service)),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return service;
  }

  FilledButton saveButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const ValueKey('edit-save')));

  // RD: the entry shows on a server without the overlay (or for a local file), and saving fails with an unknown
  // endpoint; or it never shows on our server.
  testWidgets(
      'offers "Edit tags" only for a server song on a server that keeps edits',
      (tester) async {
    Future<bool> shown(bool supported, Song s) async {
      // A fresh tree: the entry asks the server once, when it is first built.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
          app(EditTagsMenuEntry(song: s), server: _Server(supported)));
      await tester.pumpAndSettle();
      return find
          .byKey(const ValueKey('edit-tags-entry'))
          .evaluate()
          .isNotEmpty;
    }

    expect(await shown(true, song), isTrue);
    expect(await shown(false, Song(id: 's2', title: 'x')), isFalse);
    expect(
        await shown(true, Song(id: 's3', title: 'x', isLocal: true)), isFalse);
  });

  // RD: Save is enabled before anything changed, and an unchanged edit is sent; or the edited text is not what is
  // saved.
  testWidgets('saves what was typed once a field changed', (tester) async {
    final service = await openSheet(tester);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('edit-title')))
            .controller!
            .text,
        'song_1');
    expect(saveButton(tester).onPressed, isNull);

    await tester.enterText(
        find.byKey(const ValueKey('edit-artist')), 'Producer A feat. Voice A');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('edit-save')));
    await tester.pumpAndSettle();

    expect(service.saves, [
      (
        title: 'song_1',
        artist: 'Producer A feat. Voice A',
        composer: '',
        album: ''
      )
    ]);
    expect(find.byType(EditTagsSheet), findsNothing);
    expect(find.text('Tags saved'), findsOneWidget);
  });

  // RD: a failed save closes the sheet as if it had worked, so the user believes an edit the server refused.
  testWidgets('keeps the sheet open with the reason when saving fails',
      (tester) async {
    final service = await openSheet(tester);
    service.failure = Exception('a song needs a title');

    await tester.enterText(find.byKey(const ValueKey('edit-title')), 'x');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('edit-save')));
    await tester.pumpAndSettle();

    expect(find.byType(EditTagsSheet), findsOneWidget);
    expect(find.textContaining('a song needs a title'), findsOneWidget);
  });

  // RD: the revert is offered for an unedited song (or hidden for an edited one), so an edit cannot be undone; or
  // the buttons overflow a phone's width once the revert is there.
  testWidgets('offers the revert only for an edited song, and reverts',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await openSheet(tester);
    expect(find.byKey(const ValueKey('edit-revert')), findsNothing);

    final service = await openSheet(tester, edited: true);
    await tester.tap(find.byKey(const ValueKey('edit-revert')));
    await tester.pumpAndSettle();

    expect(service.resets, 1);
    expect(find.text("Back to the file's tags"), findsOneWidget);
  });
}
