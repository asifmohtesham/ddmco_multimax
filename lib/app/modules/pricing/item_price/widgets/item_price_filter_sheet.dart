import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/settings_controls.dart';
import 'package:multimax/app/modules/pricing/item_price/item_price_controller.dart';

/// Validity (single choice) + scope checkboxes. Price list lives in the header
/// chips, not here.
class ItemPriceFilterSheet extends StatefulWidget {
  const ItemPriceFilterSheet({super.key});

  @override
  State<ItemPriceFilterSheet> createState() => _ItemPriceFilterSheetState();
}

class _ItemPriceFilterSheetState extends State<ItemPriceFilterSheet> {
  final c = Get.find<ItemPriceController>();
  late String validity = (c.activeFilters['validity'] as String?) ?? '';
  late bool scoped = c.activeFilters['scoped'] == true;
  late bool batch = c.activeFilters['batch'] == true;
  late bool zero = c.activeFilters['zero'] == true;

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: context.scheme.textMuted)),
      );

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
        // CheckboxListTile inside a painted Container needs its own Material.
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('Filter prices',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: s.text)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Get.back(),
                  ),
                ],
              ),
              _label(context, 'VALIDITY'),
              SettingsSegmented<String>(
                options: const [
                  SegmentOption(value: '', label: 'Any'),
                  SegmentOption(value: 'Active', label: 'Active'),
                  SegmentOption(value: 'Upcoming', label: 'Upcoming'),
                  SegmentOption(value: 'Expired', label: 'Expired'),
                ],
                value: validity,
                onChanged: (v) => setState(() => validity = v),
              ),
              _label(context, 'SCOPE'),
              CheckboxListTile(
                value: scoped,
                onChanged: (v) => setState(() => scoped = v ?? false),
                title: const Text('Has customer or supplier'),
                subtitle: const Text('Price limited to one party'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                value: batch,
                onChanged: (v) => setState(() => batch = v ?? false),
                title: const Text('Has batch'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                value: zero,
                onChanged: (v) => setState(() => zero = v ?? false),
                title: const Text('Zero rate'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Get.back();
                        c.applyFilters({});
                      },
                      child: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Get.back();
                        c.applyFilters({
                          if (validity.isNotEmpty) 'validity': validity,
                          if (scoped) 'scoped': true,
                          if (batch) 'batch': true,
                          if (zero) 'zero': true,
                        });
                      },
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
