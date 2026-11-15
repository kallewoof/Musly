import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/pick_reason.dart';
import '../../services/smart_shuffle.dart';

/// A small "why?" under the song title; tapping it lists why the song was picked.
class PickReasonChip extends StatelessWidget {
  const PickReasonChip({super.key, required this.reason});

  final PickReason reason;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      key: const ValueKey('pick-reason-chip'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        builder: (_) => PickReasonSheet(reason: reason),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.help_outline_rounded,
                size: 13, color: Colors.white.withValues(alpha: 0.55)),
            const SizedBox(width: 3),
            Text(
              l10n.pickReasonWhy,
              style: TextStyle(
                  fontSize: 12, color: Colors.white.withValues(alpha: 0.55)),
            ),
          ],
        ),
      ),
    );
  }
}

class PickReasonSheet extends StatelessWidget {
  const PickReasonSheet({super.key, required this.reason});

  final PickReason reason;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final small = Theme.of(context)
        .textTheme
        .bodySmall!
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.pickReasonTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final line in pickReasonLines(reason, l10n))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Text(line, style: small),
              ),
          ],
        ),
      ),
    );
  }
}

/// `.91`, `-.08`: two decimals without the leading zero, as the scores are all below 1 or near it.
String _fixed(double v) {
  final s = v.abs().toStringAsFixed(2);
  final digits = s.startsWith('0') ? s.substring(1) : s;
  return v < 0 ? '-$digits' : digits;
}

String _signed(double v) => v < 0 ? _fixed(v) : '+${_fixed(v)}';

/// The sheet's lines for [reason]. A mix's parts come largest first, then the random part and the total
/// the mix was ranked by, so the lines add up to it.
List<String> pickReasonLines(PickReason reason, AppLocalizations l10n) {
  switch (reason) {
    case ScoredPick():
      final terms = [...reason.terms]
        ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
      final sum = reason.termSum;
      return [
        for (final t in terms) '${_signed(t.value)}: ${_termLabel(t, l10n)}',
        if (reason.jitter != 0)
          '${_signed(reason.jitter)}: ${l10n.pickReasonRandom}',
        if (sum > 1 || sum < 0)
          l10n.pickReasonCapped(_fixed(sum.clamp(0.0, 1.0))),
        '= ${_fixed(reason.total)}: ${l10n.pickReasonTotal}',
      ];
    case TopHitPick():
      return [l10n.pickReasonTopHit(reason.plays)];
    case ListenAgainPick():
      return [l10n.pickReasonListenAgain];
    case ShufflePick():
      return [
        l10n.pickReasonShuffleListens(reason.completes, reason.skips),
        if (reason.starred)
          l10n.pickReasonShuffleStar(SmartShuffle.starWeight.round()),
        if (reason.artistMean case final mean?)
          l10n.pickReasonShuffleArtist(
              (mean * 100).round(), SmartShuffle.priorStrength.round())
        else
          l10n.pickReasonShuffleNoArtist,
        l10n.pickReasonShuffleDraw(_fixed(reason.draw), _fixed(reason.typical)),
      ];
    case RadioPick():
      final title = reason.seedTitle;
      return [
        switch (reason.source) {
          RadioSource.similar => l10n.pickReasonRadioSimilar(title),
          RadioSource.genre => l10n.pickReasonRadioGenre(title),
          RadioSource.artistTopSongs => l10n.pickReasonRadioArtistTop(title),
          RadioSource.artistSearch => l10n.pickReasonRadioArtistSearch(title),
          RadioSource.random => l10n.pickReasonRadioRandom(title),
        }
      ];
  }
}

String _termLabel(ScoreTerm t, AppLocalizations l10n) {
  final n = t.count?.round() ?? 0;
  return switch (t.factor) {
    ScoreFactor.artist => l10n.pickReasonArtist,
    ScoreFactor.genre => l10n.pickReasonGenre,
    ScoreFactor.album => l10n.pickReasonAlbum,
    ScoreFactor.artistRating => l10n.pickReasonArtistRating,
    ScoreFactor.genreRating => l10n.pickReasonGenreRating,
    ScoreFactor.completion => l10n.pickReasonCompletion(n),
    ScoreFactor.plays => l10n.pickReasonPlays(n),
    ScoreFactor.unheard => l10n.pickReasonUnheard,
    ScoreFactor.hourOfDay => l10n.pickReasonHourOfDay,
    ScoreFactor.profileRating => l10n.pickReasonProfileRating(n),
    ScoreFactor.songRating => l10n.pickReasonSongRating(n),
    ScoreFactor.starred => l10n.pickReasonStarred,
    ScoreFactor.skips => l10n.pickReasonSkips(n),
    ScoreFactor.recentlyPlayed => l10n.pickReasonRecentlyPlayed(n),
    ScoreFactor.genreAtThisHour => l10n.pickReasonGenreAtThisHour,
  };
}
