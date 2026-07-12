import 'package:flutter/material.dart';

/// Wraps [child] and plays a brief horizontal shake whenever [trigger]
/// changes value (compare-by-equality, not just "increases") — e.g. a
/// rejection counter bumped by a controller each time a scan is refused.
///
/// A fast, pre-attentive cue for hard rejections a SnackBar can't provide as
/// quickly. Reserve it for genuine rejections (invalid/blocked scans) — not
/// routine validation states, which should fade rather than shake.
class ShakeOnTrigger extends StatefulWidget {
  final Object trigger;
  final Widget child;

  const ShakeOnTrigger({super.key, required this.trigger, required this.child});

  @override
  State<ShakeOnTrigger> createState() => _ShakeOnTriggerState();
}

class _ShakeOnTriggerState extends State<ShakeOnTrigger>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _offset = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 4.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 4.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(covariant ShakeOnTrigger oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offset,
      builder: (context, child) => Transform.translate(
        key: const ValueKey('shakeOnTriggerTransform'),
        offset: Offset(_offset.value, 0),
        child: child,
      ),
      child: widget.child,
    );
  }
}
