import 'package:flutter/material.dart';

import '../../services/subsonic_service.dart';

/// A thin faint-green line across the top of the app while requests go to the server over the local network.
/// Follows route changes as they happen; ignores pointer events, so nothing under it stops working.
class LanIndicatorBand extends StatelessWidget {
  const LanIndicatorBand({super.key, required this.service});

  final SubsonicService service;

  static const double height = 2;
  static const Color color = Color(0x9966BB6A);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<String?>(
        valueListenable: service.route,
        builder: (context, _, __) => AnimatedOpacity(
          opacity: service.routeIsLocal ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: Container(height: height, color: color),
        ),
      ),
    );
  }
}

/// Lays [child] out full size and the [LanIndicatorBand] across its top, just below the status bar: at the
/// very top edge a phone's status bar strip would hide it. Without a status bar (desktop) that is the top.
class LanIndicatorOverlay extends StatelessWidget {
  const LanIndicatorOverlay(
      {super.key, required this.service, required this.child});

  final SubsonicService service;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topLeft,
      children: [
        child,
        Positioned(
          top: MediaQuery.paddingOf(context).top,
          left: 0,
          right: 0,
          child: LanIndicatorBand(service: service),
        ),
      ],
    );
  }
}
