import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/pick_reason.dart';
import '../../services/smart_shuffle.dart';

/// Why the current song was picked, in small print under its title.
class PickReasonList extends StatelessWidget {
  const PickReasonList({super.key, required this.reason});

  final PickReason reason;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11,
      height: 1.3,
      color: Colors.white.withValues(alpha: 0.55),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      key: const ValueKey('pick-reasons'),
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final line
              in pickReasonLines(reason, AppLocalizations.of(context)!))
            Text(line,
                style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
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
        if (reason.taste < SmartShuffle.neutralTaste)
          l10n.pickReasonShuffleTowardNew(_fixed(reason.rank))
        else if (reason.taste > SmartShuffle.neutralTaste)
          l10n.pickReasonShuffleTowardFavourites(_fixed(reason.rank)),
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
