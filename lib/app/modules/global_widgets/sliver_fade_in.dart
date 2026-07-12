import 'package:flutter/material.dart';

/// Fades [sliver] in from 0 to full opacity the first time this widget is
/// mounted — for a `CustomScrollView` that swaps between heterogeneous
/// sliver branches (e.g. a skeleton `SliverToBoxAdapter` vs a real
/// `SliverGrid`/`SliverList`) driven by an `Obx`/loading-state check.
///
/// A true cross-fade (both branches coexisting while one fades out and the
/// other fades in) isn't safe here: the branches are different sliver types
/// with their own scroll/pagination behavior, and briefly overlaying two of
/// them would double-count scroll offset and childCount. Fading in whichever
/// branch just mounted gives the same "content assembling, not popping" feel
/// without touching scroll/pagination state.
///
/// Give this widget a [key] that changes with the branch (e.g.
/// `ValueKey('skeleton')` vs `ValueKey('grid')`) so switching branches
/// remounts (and re-fades) rather than updating in place.
class SliverFadeIn extends StatefulWidget {
  final Widget sliver;
  final Duration duration;

  const SliverFadeIn({
    super.key,
    required this.sliver,
    this.duration = const Duration(milliseconds: 250),
  });

  @override
  State<SliverFadeIn> createState() => _SliverFadeInState();
}

class _SliverFadeInState extends State<SliverFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      child: widget.sliver,
      builder: (context, child) =>
          SliverOpacity(opacity: _opacity.value, sliver: child!),
    );
  }
}
