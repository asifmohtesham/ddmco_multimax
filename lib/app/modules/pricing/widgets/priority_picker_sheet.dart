import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// 1–20 grid. Returns the chosen priority, `''` for "No priority", or `null`
/// when dismissed.
Future<String?> showPriorityPicker(BuildContext context, {String current = ''}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PriorityPickerSheet(current: current),
  );
}

class _PriorityPickerSheet extends StatefulWidget {
  const _PriorityPickerSheet({required this.current});

  final String current;

  @override
  State<_PriorityPickerSheet> createState() => _PriorityPickerSheetState();
}

class _PriorityPickerSheetState extends State<_PriorityPickerSheet> {
  late String _selected = widget.current;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        decoration: BoxDecoration(
          color: s.fg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
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
                    borderRadius: BorderRadius.circular(3)),
              ),
            ),
            Row(
              children: [
                Text('Priority',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: s.text)),
                const Spacer(),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 13, height: 1.45, color: s.textMuted),
                children: const [
                  TextSpan(
                      text:
                          'Higher number wins when several rules match the same line. Two matching rules with the '),
                  TextSpan(
                      text: 'same',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(
                      text: ' priority block the Delivery Note from saving.'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 5,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.4,
              children: [
                for (var i = 1; i <= 20; i++) _cell(context, '$i'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(''),
                    child: const Text('No priority'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(_selected),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, String value) {
    final s = context.scheme;
    final on = value == _selected;
    return InkWell(
      key: ValueKey('priority-$value'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _selected = value),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? s.primary : s.fg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? s.primary : s.borderStrong),
        ),
        child: Text(value,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: on ? s.onPrimary : s.text)),
      ),
    );
  }
}
