import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// A shimmer placeholder rectangle (ERPNext v15 `.skeleton`). Sweeps a
/// `subtle → border → subtle` gradient left→right on a 1.3s loop. Honours
/// reduced-motion (renders a static `subtle` fill). Colors come from
/// [BuildContext.scheme] so it adapts to light/dark.
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = AppRadius.sm,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final radius = BorderRadius.circular(widget.radius);

    if (MediaQuery.disableAnimationsOf(context)) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: s.subtle, borderRadius: radius),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final dx = (_controller.value * 2.0) - 1.0; // -1 → 1
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment(dx - 1.0, 0),
              end: Alignment(dx + 1.0, 0),
              colors: [s.subtle, s.border, s.subtle],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}
