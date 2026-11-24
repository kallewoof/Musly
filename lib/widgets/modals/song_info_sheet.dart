import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../services/recommendation_service.dart';
import '../../services/subsonic_service.dart';
import '../now_playing/pick_reason_list.dart';

/// What is known about a song: the user's listening on all devices (from the server, fetched fresh), what
/// this device recorded, why the current queue has it, and its file.
class SongInfoSheet extends StatefulWidget {
  const SongInfoSheet({super.key, required this.song});

  final Song song;

  static Future<void> show(BuildContext context, Song song) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        builder: (_) => SongInfoSheet(song: song),
      );

  @override
  State<SongInfoSheet> createState() => _SongInfoSheetState();
}

class _SongInfoSheetState extends State<SongInfoSheet> {
  late Song _song = widget.song;
  bool _loading = true;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The counts in a list or queue are as old as the list; the server has the current ones.
  Future<void> _load() async {
    if (widget.song.isLocal) {
      setState(() => _loading = false);
      return;
    }
    try {
      final fresh = (await Provider.of<SubsonicService>(context, listen: false)
              .getSongWithComposers(widget.song.id))
          .song;
      if (!mounted) return;
      setState(() {
        _song = fresh;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[SongInfo] could not load ${widget.song.id}: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _offline = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    String date(DateTime? d) => d == null
        ? l10n.songInfoNever
        : DateFormat.yMMMd(locale).add_Hm().format(d.toLocal());
    String length(int? s) =>
        s == null ? '-' : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    final device = Provider.of<RecommendationService>(context, listen: false)
        .onThisDevice(_song.id);
    final reason = Provider.of<PlayerProvider>(context, listen: false)
        .pickReasonOf(_song.id);
    final muted = theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7);

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(text, style: theme.textTheme.titleSmall),
        );
    Widget row(String key, String label, String value) => Padding(
          key: ValueKey('song-info-$key'),
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(color: muted))),
            Text(value),
          ]),
        );

    // Selectable, to copy a title or an artist (for a search) or a number.
    return SafeArea(
      child: SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_song.title,
                  style: theme.textTheme.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              if (_song.artist case final artist?)
                Text(artist, style: TextStyle(color: muted)),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
              if (_offline)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(l10n.songInfoOffline,
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
              if (!_song.isLocal) ...[
                heading(l10n.songInfoListening),
                row('plays', l10n.songInfoPlays, '${_song.playCount ?? 0}'),
                row('last-played', l10n.songInfoLastPlayed, date(_song.played)),
                row('finished', l10n.songInfoFinished,
                    '${_song.completeCount ?? 0}'),
                row('skipped', l10n.songInfoSkipped, '${_song.skipCount ?? 0}'),
                row('favourite', l10n.songInfoFavourite,
                    _song.starred == true ? l10n.songInfoYes : l10n.songInfoNo),
                row(
                    'rating',
                    l10n.songInfoRating,
                    (_song.userRating ?? 0) > 0
                        ? '${_song.userRating}/5'
                        : l10n.songInfoNoRating),
                row('added', l10n.songInfoAdded, date(_song.created)),
              ],
              heading(l10n.songInfoThisDevice),
              row('device-finished', l10n.songInfoFinished,
                  '${device.finished}'),
              row('device-skipped', l10n.songInfoSkipped, '${device.skipped}'),
              row(
                  'last-heard',
                  l10n.songInfoLastHeardHere,
                  device.lastHeard == null
                      ? l10n.songInfoNotThisWeek
                      : date(device.lastHeard)),
              if (reason != null) ...[
                heading(l10n.songInfoWhy),
                Column(
                  key: const ValueKey('song-info-why'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in pickReasonLines(reason, l10n))
                      Text(line,
                          style: TextStyle(
                              fontSize: 12,
                              color: muted,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                  ],
                ),
              ],
              heading(l10n.songInfoFile),
              row(
                  'format',
                  l10n.songInfoFormat,
                  [
                    if (_song.suffix case final s?) s.toUpperCase(),
                    if (_song.bitRate case final b?) '$b kbps',
                  ].join(', ')),
              row('length', l10n.songInfoLength, length(_song.duration)),
              if (_song.size case final size?)
                row('size', l10n.songInfoSize,
                    '${(size / (1024 * 1024)).toStringAsFixed(1)} MB'),
              if (_song.year case final year?)
                row('year', l10n.songInfoYear, '$year'),
              if (_song.genre case final genre?)
                row('genre', l10n.songInfoGenre, genre),
            ],
          ),
        ),
      ),
    );
  }
}

/// The song menu's way into [SongInfoSheet].
class SongInfoMenuEntry extends StatelessWidget {
  const SongInfoMenuEntry({super.key, required this.song, this.iconColor});

  final Song song;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => ListTile(
        key: const ValueKey('song-info-entry'),
        leading: Icon(Icons.info_outline_rounded, color: iconColor),
        title: Text(AppLocalizations.of(context)!.songInfo),
        onTap: () {
          Navigator.of(context).pop();
          SongInfoSheet.show(context, song);
        },
      );
}
