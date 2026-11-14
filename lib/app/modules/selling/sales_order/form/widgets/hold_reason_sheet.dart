import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/option_picker_sheet.dart';

/// Bottom sheet collecting the required "Reason for Hold" text before the
/// controller posts it as a comment and moves the Sales Order to On Hold
/// (v15 desk behaviour). Returns the trimmed text, or null on dismiss.
Future<String?> showHoldReasonSheet() => Get.bottomSheet<String>(
      const _HoldReasonSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );

class _HoldReasonSheet extends StatefulWidget {
  const _HoldReasonSheet();

  @override
  State<_HoldReasonSheet> createState() => _HoldReasonSheetState();
}

class _HoldReasonSheetState extends State<_HoldReasonSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get.bottomSheet already wraps its content in
    // Padding(bottom: viewInsets.bottom) (see GetModalBottomSheetRoute); an
    // extra one here double-counts the keyboard height and pushes the sheet
    // (and its hit-test area) off the top of the screen. SafeArea alone
    // handles the gesture-nav-bar inset when the keyboard is closed.
    return SafeArea(
      child: OptionPickerSheetShell(
        title: 'Reason for Hold',
        mainAxisSize: MainAxisSize.min,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Why is this order being put on hold?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) => FilledButton(
                onPressed: value.text.trim().isEmpty
                    ? null
                    : () => Get.back(result: _controller.text.trim()),
                style:
                    FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('Confirm'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
