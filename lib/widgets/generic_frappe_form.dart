import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/controllers/frappe_form_controller.dart';
import 'package:multimax/widgets/frappe_field_factory.dart';
import 'package:multimax/models/frappe_form_layout_model.dart';
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

      final sections = controller.layoutSections;

      if (sections.isEmpty) {
        return const SizedBox.shrink();
      }

      // CASE 1: Single Section (Standard Vertical Form)
      if (sections.length == 1) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(FrappeTheme.spacing),
          child: Column(
            children: [
              ..._buildFields(sections[0], controller),
              const SizedBox(height: 80), // Footer padding
            ],
          ),
        );
      }

      // CASE 2: Multiple Sections (Tabbed Layout)
      return DefaultTabController(
        length: sections.length,
        child: Column(
          children: [
            // --- Tab Bar ---
            Container(
              color: Colors.white,
              width: double.infinity,
              child: TabBar(
                isScrollable: sections.length > 3,
                // Scroll if many tabs
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
                tabs: sections
                    .map((s) => Tab(text: s.label.toUpperCase(), height: 48))
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
                  children: sections.map((section) {
                    return _FrappeFormTab(
                      section: section,
                      controller: controller,
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  // Helper to build list of field widgets
  static List<Widget> _buildFields(
    FrappeFormSection section,
    FrappeFormController controller,
  ) {
    return section.fields.map((fieldConfig) {
      // Filter out layout fields that shouldn't render directly
      if ([
        'Column Break',
        'Section Break',
        'Button',
      ].contains(fieldConfig.fieldtype)) {
        return const SizedBox.shrink();
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: FrappeFieldFactory(config: fieldConfig, controller: controller),
      );
    }).toList();
  }
}

// --- Stateful Tab Wrapper for KeepAlive ---
class _FrappeFormTab extends StatefulWidget {
  final FrappeFormSection section;
  final FrappeFormController controller;

  const _FrappeFormTab({required this.section, required this.controller});

  @override
  State<_FrappeFormTab> createState() => _FrappeFormTabState();
}

class _FrappeFormTabState extends State<_FrappeFormTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // Preserves scroll position & input state

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by Mixin
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          ...GenericFrappeForm._buildFields(widget.section, widget.controller),
          const SizedBox(height: 80), // Bottom padding for sticky Save button
        ],
      ),
    );
  }
}
