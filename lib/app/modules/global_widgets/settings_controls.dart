import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// A title/subtitle row with a trailing [Switch]. The design's `.ua-switchrow`.
class SettingsSwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s3, vertical: AppSpace.s2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: s.text)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!,
                        style: TextStyle(fontSize: 12.5, color: s.textMuted)),
                  ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// A labelled integer slider with a live value readout. The design's
/// `.ua-sliderrow`. Emits rounded ints in [min]..[max].
class SettingsSliderRow extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final String suffix;
  final String? help;
  final ValueChanged<int> onChanged;

  const SettingsSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.suffix = '',
    this.help,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final v = value.toDouble().clamp(min.toDouble(), max.toDouble());
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.s3, AppSpace.s2, AppSpace.s3, AppSpace.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontSize: 14, color: s.text)),
              Text('$value$suffix',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: s.primary)),
            ],
          ),
          if (help != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(help!,
                  style: TextStyle(fontSize: 11.5, color: s.textMuted)),
            ),
          Slider(
            value: v,
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            label: '$value$suffix',
            onChanged: (d) => onChanged(d.round()),
          ),
        ],
      ),
    );
  }
}

class SegmentOption<T> {
  final T value;
  final String label;
  final IconData? icon;
  const SegmentOption({required this.value, required this.label, this.icon});
}

/// A pill segmented control. The design's `.ua-seg` / `.ua-segrow`. The
/// selected segment fills with [AppScheme.fg] over the [AppScheme.subtle] track.
class SettingsSegmented<T> extends StatelessWidget {
  final List<SegmentOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  const SettingsSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: s.subtle,
        border: Border.all(color: s.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          for (final o in options) Expanded(child: _segment(context, o)),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, SegmentOption<T> o) {
    final s = context.scheme;
    final selected = o.value == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(o.value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: selected ? s.fg : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (o.icon != null) ...[
              Icon(o.icon, size: 16, color: selected ? s.primary : s.textMuted),
              const SizedBox(width: 6),
            ],
            Text(o.label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? s.primary : s.textMuted)),
          ],
        ),
      ),
    );
  }
}
