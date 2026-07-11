import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/doc_picker_field.dart';
import 'package:multimax/app/modules/global_widgets/doc_section_card.dart';
import 'package:multimax/app/modules/global_widgets/doctype_form_header.dart';
import 'package:multimax/app/modules/todo/form/todo_form_controller.dart';

class ToDoFormScreen extends GetView<ToDoFormController> {
  const ToDoFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final t = controller.todo.value;
      final isEditable = controller.isEditable;
      final isDirty = controller.isDirty.value;
      final isSaving = controller.isSaving.value;
      final saveResult = controller.saveResult.value;
      final isLoading = controller.isLoading.value;
      final canShowClose = controller.canShowCloseAction;

      final String title =
          t == null ? 'Loading...' : (t.name == 'New ToDo' ? 'New ToDo' : t.name);

      final VoidCallback? onSave = isEditable ? controller.saveDocument : null;
      final VoidCallback? onReload =
          controller.mode != 'new' ? controller.reloadDocument : null;

      return PopScope(
        canPop: !isDirty,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await controller.confirmDiscard();
        },
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: NestedScrollView(
            headerSliverBuilder: (ctx, _) => [
              DocTypeFormHeader(
                title: title,
                docType: 'ToDo',
                statusLabel: controller.status.value,
                canSave: isDirty,
                isSaving: isSaving,
                saveResult: saveResult,
                onSave: onSave,
                onReload: onReload,
                extraActions: [
                  if (canShowClose)
                    AsyncIconButton(
                      busy: controller.isClosing,
                      onPressed: controller.toggleCloseReopen,
                      tooltip: controller.status.value == 'Closed'
                          ? 'Reopen'
                          : 'Close',
                      icon: Icon(
                        controller.status.value == 'Closed'
                            ? Icons.replay
                            : Icons.check_circle_outline,
                      ),
                    ),
                ],
              ),
            ],
            body: isLoading
                ? const Center(child: CircularProgressIndicator())
                : t == null
                    ? _buildNotFound(context)
                    : _buildBody(context),
          ),
        ),
      );
    });
  }

  // ── Not-found fallback ───────────────────────────────────────────────
  //
  // Reached when this ToDo can't be individually fetched (deleted, or a
  // permission mismatch between the query that surfaced it — e.g. the
  // Dashboard's owner/allocated_to scan — and single-document read access).
  // The header back arrow only renders when there's a route to pop to
  // (canPop derives from the navigator stack), so a deep-linked entry with
  // no prior route would otherwise strand the user; this button always
  // offers a working way back to the ToDo list regardless of back-stack.
  Widget _buildNotFound(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off,
                size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            const Text('ToDo not found.'),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: () => Get.offNamed(AppRoutes.TODO),
              icon: const Icon(Icons.checklist),
              label: const Text('Go to ToDos'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Body ─────────────────────────────────────────────────────────────

  Widget _buildBody(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DocSectionCard(
            title: 'Task',
            margin: EdgeInsets.zero,
            children: [
              TextFormField(
                controller: controller.descriptionController,
                readOnly: !controller.isEditable,
                minLines: 3,
                maxLines: 8,
                style: TextStyle(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: 'Description',
                  hintText: 'What needs to be done?',
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: colorScheme.surface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildDetailsSection(context),
          const SizedBox(height: 16),
          _buildReferenceSection(context),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ── Details section ──────────────────────────────────────────────────

  Widget _buildDetailsSection(BuildContext context) {
    return Obx(() {
      final editable = controller.isEditable;
      return DocSectionCard(
        title: 'Details',
        margin: EdgeInsets.zero,
        children: [
          Row(
            children: [
              Expanded(
                child: DocPickerField(
                  label: 'Status',
                  icon: Icons.flag_outlined,
                  value: controller.status.value,
                  onTap: editable
                      ? () => _showOptionPicker(
                            context,
                            title: 'Select Status',
                            options: ToDoFormController.statusOptions,
                            selected: controller.status.value,
                            onSelected: controller.setStatus,
                          )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DocPickerField(
                  label: 'Priority',
                  icon: Icons.priority_high_outlined,
                  value: controller.priority.value,
                  onTap: editable
                      ? () => _showOptionPicker(
                            context,
                            title: 'Select Priority',
                            options: ToDoFormController.priorityOptions,
                            selected: controller.priority.value,
                            onSelected: controller.setPriority,
                          )
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DocPickerField(
            label: 'Date',
            icon: Icons.event_outlined,
            value: controller.date.value,
            placeholder: 'No date set',
            trailingIcon: Icons.edit_calendar_outlined,
            onTap: editable ? controller.pickDate : null,
          ),
          if (editable && controller.date.value.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: controller.clearDate,
                child: const Text('Clear date'),
              ),
            ),
          const SizedBox(height: 12),
          DocPickerField(
            label: 'Assigned To',
            icon: Icons.person_outline,
            value: controller.allocatedToDisplay.value.isNotEmpty
                ? controller.allocatedToDisplay.value
                : controller.allocatedTo.value,
            placeholder: 'Unassigned',
            trailingIcon: Icons.chevron_right,
            onTap: editable ? controller.showAllocatedToPicker : null,
          ),
          if (editable && controller.allocatedTo.value.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: controller.clearAllocatedTo,
                child: const Text('Clear assignment'),
              ),
            ),
        ],
      );
    });
  }

  // ── Reference section ────────────────────────────────────────────────

  Widget _buildReferenceSection(BuildContext context) {
    return Obx(() {
      final refType = controller.referenceType.value;
      final refName = controller.referenceName.value;
      final editable = controller.isEditable;

      VoidCallback? nameOnTap;
      IconData nameTrailingIcon = Icons.chevron_right;
      if (editable) {
        nameOnTap =
            refType.isEmpty ? null : () => _showReferenceNamePicker(context);
      } else if (refType.isNotEmpty && refName.isNotEmpty) {
        final target = searchTargetForDoctype(refType);
        if (target != null) {
          nameOnTap = () =>
              Get.toNamed(target.route, arguments: target.argsFor(refName));
          nameTrailingIcon = Icons.open_in_new;
        }
      }

      return DocSectionCard(
        title: 'Reference',
        margin: EdgeInsets.zero,
        children: [
          DocPickerField(
            label: 'Reference Type',
            icon: Icons.category_outlined,
            value: refType,
            placeholder: 'None',
            onTap: editable ? () => _showReferenceTypePicker(context) : null,
          ),
          if (refType.isNotEmpty) ...[
            const SizedBox(height: 12),
            DocPickerField(
              label: 'Reference Document',
              icon: Icons.link,
              value: refName,
              placeholder: editable ? 'Select document' : 'None',
              trailingIcon: nameTrailingIcon,
              onTap: nameOnTap,
            ),
          ],
        ],
      );
    });
  }

  // ── Status / Priority option picker ─────────────────────────────────

  void _showOptionPicker(
    BuildContext context, {
    required String title,
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    Get.bottomSheet(
      SafeArea(
        child: _PickerSheetShell(
          title: title,
          mainAxisSize: MainAxisSize.min,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in options)
                ListTile(
                  title: Text(option),
                  trailing:
                      option == selected ? const Icon(Icons.check) : null,
                  onTap: () {
                    Navigator.of(context).pop();
                    onSelected(option);
                  },
                ),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  // ── Reference-type picker ────────────────────────────────────────────

  void _showReferenceTypePicker(BuildContext context) {
    final options = controller.referenceTypeOptions;
    Get.bottomSheet(
      SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return _PickerSheetShell(
              title: 'Select Reference Type',
              child: Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    if (controller.referenceType.value.isNotEmpty)
                      ListTile(
                        leading: const Icon(Icons.link_off),
                        title: const Text('None'),
                        subtitle: const Text('Clear reference'),
                        onTap: () {
                          Navigator.of(context).pop();
                          controller.clearReference();
                        },
                      ),
                    for (final target in options)
                      ListTile(
                        leading: Icon(target.icon, color: target.color),
                        title: Text(target.label),
                        onTap: () {
                          Navigator.of(context).pop();
                          controller.setReferenceType(target.doctype);
                        },
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      isScrollControlled: true,
    );
  }

  // ── Reference-document picker ────────────────────────────────────────

  void _showReferenceNamePicker(BuildContext context) {
    controller.searchReferenceDocs('');
    Timer? debounce;

    Get.bottomSheet(
      SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return _PickerSheetShell(
              title: 'Select ${controller.referenceType.value}',
              child: Expanded(
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      onChanged: (val) {
                        debounce?.cancel();
                        debounce =
                            Timer(const Duration(milliseconds: 300), () {
                          controller.searchReferenceDocs(val);
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Obx(() {
                        if (controller.isSearchingReference.value) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final results = controller.referenceSearchResults;
                        if (results.isEmpty) {
                          return const Center(child: Text('No results'));
                        }
                        return ListView.separated(
                          controller: scrollController,
                          itemCount: results.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final item = results[i];
                            return ListTile(
                              title: Text(item.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: item.subtitle != null
                                  ? Text(item.subtitle!)
                                  : Text(item.id),
                              onTap: () {
                                Navigator.of(context).pop();
                                controller.setReferenceName(item.id);
                              },
                            );
                          },
                        );
                      }),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      isScrollControlled: true,
    ).whenComplete(() => debounce?.cancel());
  }
}

// ---------------------------------------------------------------------------
// _PickerSheetShell — shared chrome for this screen's bottom-sheet pickers:
// a rounded surface container with a title row (+ close button). Extracted
// so a future contrast/safe-area fix only needs applying once for all
// three ToDo-form pickers, instead of three hand-rolled copies.
// ---------------------------------------------------------------------------

class _PickerSheetShell extends StatelessWidget {
  final String title;
  final Widget child;
  final MainAxisSize mainAxisSize;

  const _PickerSheetShell({
    required this.title,
    required this.child,
    this.mainAxisSize = MainAxisSize.max,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      child: Column(
        mainAxisSize: mainAxisSize,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
