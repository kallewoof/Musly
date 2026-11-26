import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/library_provider.dart';
import '../../services/recommendation_service.dart';
import '../../services/smart_shuffle.dart';
import '../../widgets/modals/song_info_sheet.dart';
import '../../widgets/taste_map/taste_map_chart.dart';

/// Every song in the library by when it was last played and how much Smart Shuffle believes the user likes
/// it, coloured by its play count.
class TasteMapScreen extends StatefulWidget {
  const TasteMapScreen({super.key});

  @override
  State<TasteMapScreen> createState() => _TasteMapScreenState();
}

class _TasteMapScreenState extends State<TasteMapScreen> {
  TasteMapSelection? _selection;
  bool _asList = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final songs = context
        .watch<LibraryProvider>()
        .cachedAllSongs
        .where((s) => !s.isLocal)
        .toList();
    final believed = SmartShuffle.beliefs(
        songs, context.watch<RecommendationService>().listenOutcomes);
    final points = [
      for (final s in songs) TasteMapPoint(s, believed[s.id]!.typical)
    ];
    final locale = Localizations.localeOf(context).toLanguageTag();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tasteMap),
        actions: [
          IconButton(
            icon: Icon(_asList
                ? CupertinoIcons.chart_bar_alt_fill
                : CupertinoIcons.list_bullet),
            tooltip: _asList ? l10n.tasteMapShowChart : l10n.tasteMapShowList,
            onPressed: () => setState(() => _asList = !_asList),
          ),
        ],
      ),
      body: SafeArea(
        child: points.isEmpty
            ? Center(child: Text(l10n.tasteMapEmpty))
            : _asList
                ? _list(points, l10n, locale)
                : _chart(points, l10n, locale),
      ),
    );
  }

  Widget _chart(
      List<TasteMapPoint> points, AppLocalizations l10n, String locale) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final ramp =
        theme.brightness == Brightness.dark ? playsRampDark : playsRampLight;
    final selection = _selection;
    // Looked up afresh, so a selection shows the song's (or band's) current numbers.
    final Widget detail = switch (selection) {
      SelectedSong(:final point) => points
              .where((p) => p.song.id == point.song.id)
              .map((p) => _songTile(p, l10n, locale, dense: false))
              .firstOrNull ??
          const SizedBox.shrink(),
      SelectedBand(:final band) => Text(
          l10n.tasteMapBand(
              points
                  .where((p) =>
                      p.played == null &&
                      TasteMapGeometry.bandOf(p.liking) == band.index)
                  .length,
              (band.from * 100).round(),
              (band.to * 100).round()),
          style: theme.textTheme.bodyMedium),
      null => Text(l10n.tasteMapTapHint,
          style: theme.textTheme.bodySmall?.copyWith(color: muted)),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.tasteMapHint,
              style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l10n.tasteMapPlaysLegend,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              for (var i = 0; i < playsStepLabels.length; i++)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: ramp[i], borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 4),
                  Text(playsStepLabels[i], style: theme.textTheme.bodySmall),
                ]),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TasteMapChart(
              points: points,
              now: DateTime.now(),
              selection: _selection,
              labels: TasteMapLabels(
                like: l10n.tasteMapLike,
                neutral: l10n.tasteMapNeutral,
                dislike: l10n.tasteMapDislike,
                neverPlayed: l10n.tasteMapNeverPlayed,
                now: l10n.tasteMapNow,
                locale: locale,
              ),
              onSelect: (s) => setState(() => _selection = s),
            ),
          ),
          const SizedBox(height: 8),
          detail,
        ],
      ),
    );
  }

  Widget _list(
      List<TasteMapPoint> points, AppLocalizations l10n, String locale) {
    final sorted = [...points]..sort((a, b) => b.liking.compareTo(a.liking));
    return ListView.builder(
      itemCount: sorted.length,
      itemBuilder: (_, i) => _songTile(sorted[i], l10n, locale, dense: true),
    );
  }

  Widget _songTile(TasteMapPoint p, AppLocalizations l10n, String locale,
      {required bool dense}) {
    final played = p.played;
    final details = [
      p.song.knownArtist,
      l10n.tasteMapLiking((p.liking * 100).round()),
      '${l10n.songInfoPlays} ${p.plays}',
      '${l10n.songInfoLastPlayed} ${played == null ? l10n.songInfoNever : DateFormat.MMMd(locale).format(played.toLocal())}',
    ].whereType<String>().join(' · ');
    return ListTile(
      dense: dense,
      contentPadding: dense ? null : EdgeInsets.zero,
      title: Text(p.song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(CupertinoIcons.info_circle),
      onTap: () => SongInfoSheet.show(context, p.song),
    );
  }
}
