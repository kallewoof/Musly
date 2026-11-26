import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../models/song.dart';

/// One song on the taste map: how much it is believed to be liked (0 to 1, 0.5 neutral) and when it was last
/// played, if ever.
class TasteMapPoint {
  const TasteMapPoint(this.song, this.liking);

  final Song song;
  final double liking;

  DateTime? get played => song.played;
  int get plays => song.playCount ?? 0;
}

/// The colour step of a play count: 0, 1, 2-3, 4-7, 8 or more.
int playsStep(int plays) => plays <= 0
    ? 0
    : plays == 1
        ? 1
        : plays <= 3
            ? 2
            : plays <= 7
                ? 3
                : 4;

/// The legend's label for each step of [playsStep].
const playsStepLabels = ['0', '1', '2-3', '4-7', '8+'];

/// One blue, light to dark with the play count, validated against each theme's background: the step nearest
/// the background still clears 2:1, and neighbouring steps differ visibly.
const playsRampLight = [
  Color(0xFF6AABF1),
  Color(0xFF338CED),
  Color(0xFF2370CD),
  Color(0xFF1757AC),
  Color(0xFF0E3D7E),
];
const playsRampDark = [
  Color(0xFF1757AC),
  Color(0xFF2370CD),
  Color(0xFF338CED),
  Color(0xFF6AABF1),
  Color(0xFFB6D5F8),
];

/// A band of the never-played lane: the songs whose liking falls in it.
class LaneBand {
  const LaneBand(this.index, this.songs);

  final int index;
  final List<TasteMapPoint> songs;

  double get from => index / TasteMapGeometry.bands;
  double get to => (index + 1) / TasteMapGeometry.bands;
}

/// Where everything sits in a chart of [size]. Songs played are blocks, left to right by their last play from
/// the oldest to [now]; songs never played are too many for blocks (they share their artist's starting
/// liking), so the lane at the left counts them per band of liking. Liking runs from the bottom (disliked) to
/// the top (liked).
class TasteMapGeometry {
  TasteMapGeometry(List<TasteMapPoint> points, this.size, {required this.now})
      : played = [
          for (final p in points)
            if (p.played != null) p
        ],
        oldest = points
            .map((p) => p.played)
            .whereType<DateTime>()
            .fold<DateTime?>(
                null, (a, b) => a == null || b.isBefore(a) ? b : a) {
    final byBand = List.generate(bands, (_) => <TasteMapPoint>[]);
    for (final p in points) {
      if (p.played == null) byBand[bandOf(p.liking)].add(p);
    }
    lane = [for (var i = 0; i < bands; i++) LaneBand(i, byBand[i])];
    final counts = lane.map((b) => b.songs.length).toList()..sort();
    final fullest = counts.last;
    final next = counts[counts.length - 2];
    // One band can dwarf the rest (songs with no history at all sit at exactly neutral); scaled to it, the
    // others would be slivers. Bars then scale to the next fullest, and the outlier is drawn broken.
    _barScale = next > 0 && fullest > 2 * next ? next : fullest;
    placed = [
      for (final p in played) (p, Offset(xOf(p.played!), yOf(p.liking)))
    ];
  }

  static const double block = 8;
  static const double laneWidth = 64;
  static const double gap = 14;
  static const double bottomAxis = 30;
  static const double hitRadius = 16;

  /// The lane's bands of liking: 2.5 percentage points each.
  static const int bands = 40;

  final Size size;
  final DateTime now;
  final List<TasteMapPoint> played;

  /// The oldest last play; null when no song was played.
  final DateTime? oldest;

  late final List<LaneBand> lane;
  late final List<(TasteMapPoint, Offset)> placed;
  late final int _barScale;

  /// Whether [band]'s bar is too long to draw to scale: it is drawn full width, broken, with its count.
  bool isBroken(LaneBand band) => band.songs.length > _barScale;

  static int bandOf(double liking) =>
      math.min(bands - 1, (liking.clamp(0.0, 1.0) * bands).floor());

  Rect get laneRect =>
      Rect.fromLTWH(0, block / 2, laneWidth, size.height - bottomAxis - block);

  Rect get plot => Rect.fromLTRB(laneWidth + gap + block / 2, laneRect.top,
      size.width - block / 2, laneRect.bottom);

  double yOf(double liking) =>
      plot.bottom - liking.clamp(0.0, 1.0) * plot.height;

  double xOf(DateTime played) {
    final from = oldest!;
    final span = now.difference(from).inMilliseconds;
    if (span <= 0) return plot.right;
    final t = played.difference(from).inMilliseconds / span;
    return plot.left + t.clamp(0.0, 1.0) * plot.width;
  }

  /// A band's bar: as long as its count on the lane's scale (full width for a [isBroken] one), and at least
  /// visible when not empty.
  Rect? barOf(LaneBand band) {
    if (band.songs.isEmpty) return null;
    final width = math.max(
        3.0, laneRect.width * math.min(1.0, band.songs.length / _barScale));
    final top = yOf(band.to);
    final bottom = yOf(band.from);
    return Rect.fromLTRB(laneRect.right - width, top + 0.5, laneRect.right,
        math.max(top + 1.5, bottom - 0.5));
  }

  /// The song nearest [at] within [hitRadius], if any.
  TasteMapPoint? hit(Offset at) {
    TasteMapPoint? best;
    var bestDistance = hitRadius;
    for (final (p, o) in placed) {
      final d = (o - at).distance;
      if (d <= bestDistance) {
        best = p;
        bestDistance = d;
      }
    }
    return best;
  }

  /// The lane band at [at], if it holds songs.
  LaneBand? hitLane(Offset at) {
    if (at.dx > laneRect.right + gap / 2 ||
        at.dy < laneRect.top ||
        at.dy > laneRect.bottom) {
      return null;
    }
    final liking = (plot.bottom - at.dy) / plot.height;
    final band = lane[bandOf(liking)];
    return band.songs.isEmpty ? null : band;
  }
}

/// What is selected on the map: a song, or a band of the never-played lane.
sealed class TasteMapSelection {
  const TasteMapSelection();
}

class SelectedSong extends TasteMapSelection {
  const SelectedSong(this.point);
  final TasteMapPoint point;
}

class SelectedBand extends TasteMapSelection {
  const SelectedBand(this.band);
  final LaneBand band;
}

/// Draws a [TasteMapGeometry]: the blocks, coloured by play count, the lane's bars, the neutral line and the
/// axes.
class TasteMapPainter extends CustomPainter {
  TasteMapPainter({
    required this.geometry,
    required this.ramp,
    required this.surface,
    required this.ink,
    required this.grid,
    required this.labelStyle,
    required this.labels,
    this.selectedSong,
    this.selectedBand,
  });

  final TasteMapGeometry geometry;
  final List<Color> ramp;
  final Color surface;
  final Color ink;
  final Color grid;
  final TextStyle labelStyle;
  final TasteMapLabels labels;
  final String? selectedSong;
  final int? selectedBand;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final selection = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // The neutral line, across lane and plot, and the lane's edge.
    final neutral = g.yOf(0.5);
    canvas.drawLine(Offset(g.laneRect.left, neutral),
        Offset(g.plot.right, neutral), gridPaint);
    final edge = g.laneRect.right + TasteMapGeometry.gap / 2;
    canvas.drawLine(Offset(edge, g.laneRect.top),
        Offset(edge, g.laneRect.bottom), gridPaint);

    // The lane: never-played songs have no plays, so the bars take the first step.
    for (final band in g.lane) {
      final bar = g.barOf(band);
      if (bar == null) continue;
      final r = RRect.fromRectAndCorners(bar,
          topLeft: const Radius.circular(2),
          bottomLeft: const Radius.circular(2));
      canvas.drawRRect(r, Paint()..color = ramp[0]);
      if (g.isBroken(band)) {
        final x = bar.left + 10;
        canvas.drawLine(
            Offset(x, bar.bottom + 1),
            Offset(x + 6, bar.top - 1),
            Paint()
              ..color = surface
              ..strokeWidth = 3);
        final count = _measure('${band.songs.length}');
        _backdropText(canvas, count, Offset(bar.left, bar.top - count.height));
      }
      if (band.index == selectedBand) canvas.drawRRect(r.inflate(2), selection);
    }

    // Least played first, so the songs played most are not buried.
    final order = [...g.placed]
      ..sort((a, b) => a.$1.plays.compareTo(b.$1.plays));
    final ring = Paint()
      ..color = surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    Offset? chosen;
    for (final (p, o) in order) {
      final r = RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: o,
              width: TasteMapGeometry.block,
              height: TasteMapGeometry.block),
          const Radius.circular(2));
      canvas.drawRRect(r, Paint()..color = ramp[playsStep(p.plays)]);
      canvas.drawRRect(r.inflate(0.75), ring);
      if (p.song.id == selectedSong) chosen = o;
    }
    if (chosen != null) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: chosen,
                  width: TasteMapGeometry.block + 6,
                  height: TasteMapGeometry.block + 6),
              const Radius.circular(4)),
          selection);
    }

    // Liking labels at the lane's left, where its bars (drawn from the right) leave room, on a backdrop where
    // one does not; time labels under the plot; the lane's name under the lane.
    final like = _measure(labels.like);
    final neutralLabel = _measure(labels.neutral);
    final dislike = _measure(labels.dislike);
    _backdropText(canvas, like, Offset(g.laneRect.left, g.plot.top));
    _backdropText(canvas, neutralLabel, Offset(g.laneRect.left, neutral + 2));
    _backdropText(canvas, dislike,
        Offset(g.laneRect.left, g.plot.bottom - dislike.height));
    final axisY = g.laneRect.bottom + TasteMapGeometry.block / 2 + 4;
    _text(canvas, labels.neverPlayed, Offset(g.laneRect.left, axisY),
        maxWidth: g.laneRect.width + TasteMapGeometry.gap);
    if (g.oldest != null) {
      _text(canvas, labels.date(g.oldest!), Offset(g.plot.left, axisY));
      _text(canvas, labels.now, Offset(g.plot.right, axisY), alignRight: true);
    }
  }

  TextPainter _measure(String text, {double maxWidth = 160}) => TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 2,
      )..layout(maxWidth: maxWidth);

  void _backdropText(Canvas canvas, TextPainter tp, Offset at) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            (at & tp.size).inflate(2), const Radius.circular(3)),
        Paint()..color = surface.withValues(alpha: 0.85));
    tp.paint(canvas, at);
  }

  void _text(Canvas canvas, String text, Offset at,
      {double maxWidth = 160, bool alignRight = false}) {
    final tp = _measure(text, maxWidth: maxWidth);
    tp.paint(canvas, alignRight ? at.translate(-tp.width, 0) : at);
  }

  @override
  bool shouldRepaint(TasteMapPainter old) =>
      old.geometry != geometry ||
      old.selectedSong != selectedSong ||
      old.selectedBand != selectedBand ||
      old.ramp != ramp ||
      old.surface != surface ||
      old.labelStyle != labelStyle;
}

/// The chart's words, from the app's translations.
class TasteMapLabels {
  const TasteMapLabels({
    required this.like,
    required this.neutral,
    required this.dislike,
    required this.neverPlayed,
    required this.now,
    required this.locale,
  });

  final String like;
  final String neutral;
  final String dislike;
  final String neverPlayed;
  final String now;
  final String locale;

  String date(DateTime d) => DateFormat.MMMd(locale).format(d.toLocal());
}

/// The chart, sized to its parent, reporting what is tapped (or hovered, with a mouse).
class TasteMapChart extends StatelessWidget {
  const TasteMapChart({
    super.key,
    required this.points,
    required this.now,
    required this.labels,
    required this.onSelect,
    this.selection,
  });

  final List<TasteMapPoint> points;
  final DateTime now;
  final TasteMapLabels labels;
  final ValueChanged<TasteMapSelection> onSelect;
  final TasteMapSelection? selection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ink = theme.colorScheme.onSurface;
    return LayoutBuilder(builder: (context, constraints) {
      final size =
          Size(constraints.maxWidth, math.max(160.0, constraints.maxHeight));
      final geometry = TasteMapGeometry(points, size, now: now);
      void pick(Offset at) {
        final song = geometry.hit(at);
        if (song != null) return onSelect(SelectedSong(song));
        final band = geometry.hitLane(at);
        if (band != null) onSelect(SelectedBand(band));
      }

      final selected = selection;
      return MouseRegion(
        onHover: (e) => pick(e.localPosition),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => pick(d.localPosition),
          child: CustomPaint(
            size: size,
            painter: TasteMapPainter(
              geometry: geometry,
              ramp: dark ? playsRampDark : playsRampLight,
              surface: theme.scaffoldBackgroundColor,
              ink: ink,
              grid: ink.withValues(alpha: 0.15),
              labelStyle: (theme.textTheme.labelSmall ?? const TextStyle())
                  .copyWith(color: ink.withValues(alpha: 0.6)),
              labels: labels,
              selectedSong:
                  selected is SelectedSong ? selected.point.song.id : null,
              selectedBand:
                  selected is SelectedBand ? selected.band.index : null,
            ),
          ),
        ),
      );
    });
  }
}
