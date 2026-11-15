import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/song.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../services/subsonic_service.dart';
import '../../services/tag_edit_service.dart';

/// Edits a song's title, artist credit, composer and album on the server, without touching its file.
class EditTagsSheet extends StatefulWidget {
  const EditTagsSheet({super.key, required this.song, required this.service});

  final Song song;
  final TagEditService service;

  static Future<void> show(BuildContext context, Song song) {
    final service = TagEditService(
      Provider.of<SubsonicService>(context, listen: false),
      Provider.of<LibraryProvider>(context, listen: false),
      Provider.of<PlayerProvider>(context, listen: false),
    );
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => EditTagsSheet(song: song, service: service),
    );
  }

  @override
  State<EditTagsSheet> createState() => _EditTagsSheetState();
}

class _EditTagsSheetState extends State<EditTagsSheet> {
  final _title = TextEditingController();
  final _artist = TextEditingController();
  final _composer = TextEditingController();
  final _album = TextEditingController();
  TagFields? _initial;
  bool _edited = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _artist, _composer, _album]) {
      c.addListener(() => setState(() {}));
    }
    widget.service.load(widget.song.id).then((loaded) {
      if (!mounted) return;
      final f = loaded.fields;
      _title.text = f.title;
      _artist.text = f.artist;
      _composer.text = f.composer;
      _album.text = f.album;
      setState(() {
        _initial = f;
        _edited = loaded.edited;
      });
    }, onError: (Object e) {
      if (!mounted) return;
      setState(() =>
          _error = AppLocalizations.of(context)!.editTagsLoadFailed('$e'));
    });
  }

  @override
  void dispose() {
    for (final c in [_title, _artist, _composer, _album]) {
      c.dispose();
    }
    super.dispose();
  }

  TagFields get _fields => (
        title: _title.text,
        artist: _artist.text,
        composer: _composer.text,
        album: _album.text,
      );

  bool get _changed {
    final i = _initial;
    if (i == null) return false;
    final f = _fields;
    return f.title.trim() != i.title.trim() ||
        f.artist.trim() != i.artist.trim() ||
        f.composer.trim() != i.composer.trim() ||
        f.album.trim() != i.album.trim();
  }

  Future<void> _run(Future<Song?> Function() action, String done) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final song = await action();
      navigator.pop();
      messenger.showSnackBar(
          SnackBar(content: Text(song != null ? done : l10n.editTagsPending)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l10n.editTagsFailed('$e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final loading = _initial == null && _error == null;
    Widget field(TextEditingController c, String key, String label,
            {String? hint}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            key: ValueKey(key),
            controller: c,
            enabled: !_busy,
            decoration: InputDecoration(labelText: label, hintText: hint),
          ),
        );
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.editTags,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              if (loading)
                const Center(child: CircularProgressIndicator())
              else if (_initial != null) ...[
                field(_title, 'edit-title', l10n.editTagsTitle),
                field(_artist, 'edit-artist', l10n.editTagsArtist,
                    hint: l10n.editTagsArtistHint),
                field(_composer, 'edit-composer', l10n.editTagsComposer),
                field(_album, 'edit-album', l10n.editTagsAlbum),
                if (_edited)
                  Text(l10n.editTagsEditedNote,
                      style: Theme.of(context).textTheme.bodySmall),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      key: const ValueKey('edit-error'),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 16),
              if (_edited)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    key: const ValueKey('edit-revert'),
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () =>
                                widget.service.reset(widget.song.id, _initial!),
                            l10n.editTagsReverted),
                    child: Text(l10n.editTagsRevert),
                  ),
                ),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('edit-save'),
                    onPressed: _busy || !_changed
                        ? null
                        : () => _run(
                            () => widget.service
                                .save(widget.song.id, _initial!, _fields),
                            l10n.editTagsSaved),
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(l10n.save),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "Edit tags" menu entry: shown for a server song when the server keeps tag edits, and opening the editor
/// in place of the menu.
class EditTagsMenuEntry extends StatefulWidget {
  const EditTagsMenuEntry({super.key, required this.song, this.iconColor});

  final Song song;
  final Color? iconColor;

  @override
  State<EditTagsMenuEntry> createState() => _EditTagsMenuEntryState();
}

class _EditTagsMenuEntryState extends State<EditTagsMenuEntry> {
  late final Future<bool> _supported = widget.song.isLocal
      ? Future.value(false)
      : Provider.of<SubsonicService>(context, listen: false)
          .supportsTagOverlay();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _supported,
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        return ListTile(
          key: const ValueKey('edit-tags-entry'),
          leading: Icon(Icons.edit_note_rounded, color: widget.iconColor),
          title: Text(AppLocalizations.of(context)!.editTags),
          onTap: () {
            Navigator.of(context).pop();
            EditTagsSheet.show(context, widget.song);
          },
        );
      },
    );
  }
}
