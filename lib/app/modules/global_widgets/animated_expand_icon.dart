import 'package:flutter/material.dart';

class AnimatedExpandIcon extends StatelessWidget {
  final bool isExpanded;
  final Duration duration;

  const AnimatedExpandIcon({
    super.key,
    required this.isExpanded,
    this.duration = const Duration(milliseconds: 300),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: isExpanded ? 0.5 : 0.0,
      duration: duration,
      child: const Icon(Icons.expand_more),
    );
  }
}
