import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// Uppercase section label rendered above a settings card (the design's
/// `.ua-glabel`). Reused by the Account hub, Session Defaults, and Theme.
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.s2, 0, AppSpace.s2, AppSpace.s2),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
          color: s.textMuted,
        ),
      ),
    );
  }
}

/// A settings section: optional [label] above a bordered card whose
/// [children] are separated by 1px hairlines (the design's `.ua-group` +
/// `.ua-card`). Colors from [BuildContext.scheme]; no shadows (border only).
class SettingsGroup extends StatelessWidget {
  final String? label;
  final List<Widget> children;
  const SettingsGroup({super.key, this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: 1, thickness: 1, color: s.border));
      }
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) SectionLabel(text: label!),
        DecoratedBox(
          decoration: BoxDecoration(
            color: s.fg,
            border: Border.all(color: s.border),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Column(mainAxisSize: MainAxisSize.min, children: rows),
          ),
        ),
      ],
    );
  }
}
