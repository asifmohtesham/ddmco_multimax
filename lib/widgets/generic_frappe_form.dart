import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/controllers/frappe_form_controller.dart';
import 'package:multimax/widgets/frappe_field_factory.dart';
import 'package:multimax/models/frappe_form_layout_model.dart';
import 'package:multimax/models/frappe_field_config.dart';
import 'package:multimax/theme/frappe_theme.dart';

class GenericFrappeForm extends StatelessWidget {
  final FrappeFormController controller;

  const GenericFrappeForm({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isMetaLoading.value) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32.0),
            child: CircularProgressIndicator(color: FrappeTheme.primary),
          ),
        );
      }

      final tabs = controller.layoutTabs;

      if (tabs.isEmpty) {
        return const SizedBox.shrink();
      }

      // CASE 1: Only 1 Tab -> Render standard vertical list
      if (tabs.length == 1) {
        return _FrappeFormTabContent(
          sections: tabs[0].sections,
          controller: controller,
          tabLabel: "Main",
        );
      }

      // CASE 2: Multiple Tabs -> Render TabBar
      return DefaultTabController(
        length: tabs.length,
        child: Column(
          children: [
            // --- Tab Bar ---
            Container(
              color: Colors.white,
              width: double.infinity,
              child: TabBar(
                isScrollable: tabs.length > 3,
                labelColor: FrappeTheme.primary,
                unselectedLabelColor: FrappeTheme.textLabel,
                indicatorColor: FrappeTheme.primary,
                indicatorWeight: 3,
                labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  fontFamily: 'Roboto',
                ),
                tabs: tabs
                    .map((t) => Tab(text: t.label.toUpperCase(), height: 48))
                    .toList(),
              ),
            ),
            const Divider(height: 1, thickness: 1, color: FrappeTheme.border),

            // --- Tab Content ---
            Expanded(
              child: Container(
                color: FrappeTheme.surface,
                child: TabBarView(
                  physics: const BouncingScrollPhysics(),
                  children: tabs
                      .map(
                        (tab) => _FrappeFormTabContent(
                          sections: tab.sections,
                          controller: controller,
                          tabLabel: tab.label,
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

// --- Stateless Tab Content ---
class _FrappeFormTabContent extends StatelessWidget {
  final List<FrappeFormSection> sections;
  final FrappeFormController controller;
  final String tabLabel;

  const _FrappeFormTabContent({
    required this.sections,
    required this.controller,
    required this.tabLabel,
  });

  @override
  Widget build(BuildContext context) {
    // PageStorageKey ensures scroll position is saved in the bucket
    // even if the widget is rebuilt or unmounted by TabBarView
    return SingleChildScrollView(
      key: PageStorageKey<String>(tabLabel),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          ...sections.map((s) => _buildSection(context, s)).toList(),
          const SizedBox(height: 80), // Footer Padding
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, FrappeFormSection section) {
    // Standard Section (No Label = Invisible container)
    if (section.label.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(children: _buildFields(section.fields)),
      );
    }

    // Collapsible Section (ExpansionTile)
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Material(
        color: Colors.white,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: Obx(
            () => ExpansionTile(
              key: PageStorageKey<String>("sec_${section.label}"),
              title: Text(
                section.label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: FrappeTheme.textBody,
                  fontSize: 15,
                ),
              ),
              // Bind Expansion State to Model
              initiallyExpanded: section.isExpanded.value,
              onExpansionChanged: (val) => section.isExpanded.value = val,

              backgroundColor: Colors.white,
              collapsedBackgroundColor: Colors.white,
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),

              children: _buildFields(section.fields),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFields(List<FrappeFieldConfig> fields) {
    return fields.map<Widget>((fieldConfig) {
      // 1. Skip Layout fields
      if ([
        'Column Break',
        'Section Break',
        'Tab Break',
        'Button',
      ].contains(fieldConfig.fieldtype)) {
        return const SizedBox.shrink();
      }

      // 2. Hide Empty ReadOnly Fields (Clutter reduction)
      if (fieldConfig.readOnly) {
        final val = controller.data[fieldConfig.fieldname];
        bool isEmpty = val == null;
        if (val is String) isEmpty = val.trim().isEmpty;
        if (val is List) isEmpty = val.isEmpty;
        if (val is num) isEmpty = false;
        if (isEmpty) return const SizedBox.shrink();
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: FrappeFieldFactory(config: fieldConfig, controller: controller),
      );
    }).toList();
  }
}
