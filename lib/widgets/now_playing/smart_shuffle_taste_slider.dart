import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/player_provider.dart';

/// Smart Shuffle's slider, from the songs heard least to those liked most. Letting go re-picks the songs
/// after the current one.
class SmartShuffleTasteSlider extends StatefulWidget {
  const SmartShuffleTasteSlider(
      {super.key, required this.color, this.compact = false});

  /// The colour of the end labels, to sit with the text around it.
  final Color color;

  /// One short row, for the desktop player bar.
  final bool compact;

  @override
  State<SmartShuffleTasteSlider> createState() =>
      _SmartShuffleTasteSliderState();
}

class _SmartShuffleTasteSliderState extends State<SmartShuffleTasteSlider> {
  /// The position while dragging; null shows the player's.
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final player = context.watch<PlayerProvider>();
    final label =
        TextStyle(fontSize: widget.compact ? 10 : 11, color: widget.color);
    Widget end(String text) => Flexible(
        child: Text(text,
            style: label, maxLines: 1, overflow: TextOverflow.ellipsis));
    final row = Row(
      key: const ValueKey('smart-shuffle-taste'),
      children: [
        end(l10n.smartShuffleTasteNew),
        Expanded(
          flex: 2,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: _dragging ?? player.smartShuffleTaste,
              semanticFormatterCallback: (_) => l10n.smartShuffleTasteLabel,
              onChanged: (v) => setState(() => _dragging = v),
              onChangeEnd: (v) {
                setState(() => _dragging = null);
                player.setSmartShuffleTaste(v);
              },
            ),
          ),
        ),
        end(l10n.smartShuffleTasteFavourites),
      ],
    );
    return widget.compact ? SizedBox(height: 20, child: row) : row;
  }
}
