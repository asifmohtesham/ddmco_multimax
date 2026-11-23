import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// The themed bottom-sheet frame for the stock sheet's questions: handle,
/// title, muted subtitle, then the options.
class ItemsFromPhotosChoiceSheet extends StatelessWidget {
  const ItemsFromPhotosChoiceSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.options,
  });

  final String title;
  final String subtitle;
  final List<Widget> options;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    // A Material (not a decorated Container) so the options' ink shows.
    return Material(
      color: s.fg,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: s.borderStrong,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: s.text,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                child: Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, color: s.textMuted),
                ),
              ),
              ...options,
            ],
          ),
        ),
      ),
    );
  }
}
