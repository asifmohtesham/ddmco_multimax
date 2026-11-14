import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/doctype_form_header.dart';

// Regression: the form header is a SliverPersistentHeader whose delegate's
// shouldRebuild keys on `extraActions?.length` — a content-only change to an
// action (e.g. swapping an icon for a loading spinner, count unchanged) does
// NOT trigger a header rebuild. Therefore a reactive extraAction must carry its
// own Obx so it updates independently of the header. This test pins that the
// Obx-wrapped action reflects observable changes through the non-rebuilding
// header (the property the PO "Create Purchase Receipt" header spinner relies
// on). Without the Obx wrapper, toggling the flag would not update the icon.
void main() {
  testWidgets(
      'Obx-wrapped header extraAction updates when its observable changes, '
      'even though the persistent-header delegate does not rebuild',
      (tester) async {
    final loading = false.obs;
    addTearDown(loading.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              DocTypeFormHeader(
                title: 'PO-1',
                docType: 'Purchase Order',
                extraActions: [
                  Obx(() => loading.value
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.receipt_long)),
                ],
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 1000)),
            ],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.receipt_long), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Flip ONLY the observable — nothing the delegate's shouldRebuild tracks
    // changes, so the header itself will not rebuild. The Obx must.
    loading.value = true;
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long), findsNothing);
  });
}
