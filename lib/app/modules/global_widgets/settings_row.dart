import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// A tappable settings row: tinted leading icon tile, title (+ optional
/// subtitle), optional trailing [value], optional chevron. The design's
/// `.ua-row`. Colors from [BuildContext.scheme].
class SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color? iconTint;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final bool showChevron;

  const SettingsRow({
    super.key,
    required this.icon,
    this.iconTint,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final tint = iconTint ?? s.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.s3, vertical: AppSpace.s3),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Color.alphaBlend(tint.withValues(alpha: 0.14), s.fg),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: tint),
            ),
            const SizedBox(width: AppSpace.s3),
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
            if (value != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(value!,
                    style: TextStyle(fontSize: 13, color: s.textMuted)),
              ),
            if (showChevron && onTap != null)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.chevron_right, size: 18, color: s.textSubtle),
              ),
          ],
        ),
      ),
    );
  }
}
