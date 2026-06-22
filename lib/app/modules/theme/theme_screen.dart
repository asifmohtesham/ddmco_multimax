import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/global_widgets/settings_group.dart';
import 'package:multimax/app/modules/global_widgets/settings_controls.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';

/// Appearance settings. Phase 1: Light / Dark / System only (accent + text
/// size land here in phase 2). A live preview card reflects the active theme.
class ThemeScreen extends StatelessWidget {
  const ThemeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tc = Get.find<ThemeController>();
    return Scaffold(
      appBar: const MainAppBar(title: 'Theme'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.s4, AppSpace.s2, AppSpace.s4, AppSpace.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel(text: 'Preview'),
            _PreviewCard(),
            const SizedBox(height: AppSpace.s4),
            const SectionLabel(text: 'Appearance'),
            Obx(() => SettingsSegmented<ThemeMode>(
                  value: tc.themeMode.value,
                  onChanged: tc.setThemeMode,
                  options: const [
                    SegmentOption(
                        value: ThemeMode.light,
                        label: 'Light',
                        icon: Icons.light_mode_outlined),
                    SegmentOption(
                        value: ThemeMode.dark,
                        label: 'Dark',
                        icon: Icons.dark_mode_outlined),
                    SegmentOption(
                        value: ThemeMode.system,
                        label: 'System',
                        icon: Icons.brightness_auto_outlined),
                  ],
                )),
            const SizedBox(height: AppSpace.s4),
            const SectionLabel(text: 'Accent color'),
            Obx(() => _AccentGrid(
                  selected: tc.accentKey.value,
                  onPick: tc.setAccent,
                )),
            const SizedBox(height: AppSpace.s4),
            const SectionLabel(text: 'Text size'),
            Obx(() => SettingsSegmented<AppTextSize>(
                  value: tc.textSize.value,
                  onChanged: tc.setTextSize,
                  options: const [
                    SegmentOption(
                        value: AppTextSize.compact, label: 'Compact'),
                    SegmentOption(
                        value: AppTextSize.comfortable, label: 'Comfortable'),
                    SegmentOption(value: AppTextSize.large, label: 'Large'),
                  ],
                )),
          ],
        ),
      ),
    );
  }
}

/// Accent swatch grid (the design's `.ua-accents`). Brand maroon first; the
/// selected swatch gets a ring + check. Swatch fill is the accent's primary
/// for the current brightness.
class _AccentGrid extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onPick;
  const _AccentGrid({required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.all(AppSpace.s3),
      decoration: BoxDecoration(
        color: s.fg,
        border: Border.all(color: s.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          for (final a in AppAccent.all)
            GestureDetector(
              key: Key('accent-${a.key}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onPick(a.key),
              child: _Swatch(
                accent: a,
                selected: a.key == selected,
                brightness: brightness,
                ringColor: s.border,
              ),
            ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final AppAccent accent;
  final bool selected;
  final Brightness brightness;
  final Color ringColor;
  const _Swatch({
    required this.accent,
    required this.selected,
    required this.brightness,
    required this.ringColor,
  });

  @override
  Widget build(BuildContext context) {
    final fill = accent.primaryFor(brightness);
    final onFill = accent.onPrimaryFor(brightness);
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (selected)
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: fill, width: 2),
              ),
            ),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
            child: selected
                ? Icon(Icons.check, size: 18, color: onFill)
                : null,
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    Widget pill(String text, {required bool filled}) => Expanded(
          child: Container(
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: filled ? s.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: filled
                  ? null
                  : Border.all(
                      color: Color.alphaBlend(
                          s.primary.withValues(alpha: 0.4), s.border)),
            ),
            child: Text(text,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: filled ? s.onPrimary : s.primary)),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(AppSpace.s4),
      decoration: BoxDecoration(
        color: s.bg,
        border: Border.all(color: s.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.s3),
        decoration: BoxDecoration(
          color: s.fg,
          border: Border.all(color: s.border),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                        s.primary.withValues(alpha: 0.16), s.fg),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(Icons.description_outlined,
                      size: 19, color: s.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Stock Entry · SE-2026',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: s.text)),
                      Text('12 items · In stock',
                          style: TextStyle(fontSize: 12, color: s.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            Row(children: [
              pill('Cancel', filled: false),
              const SizedBox(width: 8),
              pill('Submit', filled: true),
            ]),
          ],
        ),
      ),
    );
  }
}
