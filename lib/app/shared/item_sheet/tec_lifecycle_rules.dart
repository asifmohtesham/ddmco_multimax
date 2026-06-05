// ignore_for_file: unused_import
//
// This file is intentionally a documentation-only namespace.
// Import it in any file that declares a TextEditingController, FocusNode,
// or ScrollController to surface the four rules in IDE quick-docs (hover
// / F1 / Ctrl+Q) at every declaration site.
//
// Example — add to the top of any controller file:
//
//   import 'package:multimax/app/shared/item_sheet/tec_lifecycle_rules.dart'
//       show TecLifecycleRules; // docs only — tree-shaken at compile time

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// # TextEditingController (TEC) Lifecycle Rules
///
/// Every [TextEditingController], [FocusNode], and [ScrollController]
/// in this project **must** comply with all four rules below without
/// exception.  Violations cause one or more of the following runtime
/// crashes:
///
///   • `"A TextEditingController was used after being disposed."` —
///     thrown by [ChangeNotifier.debugAssertNotDisposed] when Flutter's
///     exit-animation frame calls `addListener()` on an already-disposed
///     controller.
///   • `'_dependents.isEmpty': is not true` — secondary crash in
///     [InheritedElement.debugDeactivated] when inherited-widget
///     subscriptions are still live during widget-tree teardown.
///
/// These are **not** Flutter framework bugs.  They surface deterministically
/// when:
///   1. A bottom sheet containing a [TextFormField] is dismissed while the
///      keyboard is open **or** while the exit animation is still running.
///   2. A GetX controller that owns a TEC is deleted (route pop /
///      `Get.delete`) while the animation frame that calls `addListener`
///      is still pending.
///
/// ---
///
/// ## Rule 1 — Always defer TEC disposal past the exit animation
///
/// **Never** call [TextEditingController.dispose], [FocusNode.dispose], or
/// [ScrollController.dispose] **synchronously** inside `onClose()` or any
/// other teardown method.
///
/// A bottom sheet exit animation takes ~300 ms.  When the keyboard is open
/// at dismiss time the keyboard-dismissal animation also takes ~300 ms and
/// runs concurrently.  During both animations Flutter rebuilds the widget
/// tree in response to `MediaQuery.viewInsets` changes;
/// `_EditableTextState.dispose()` calls `removeListener()` only after the
/// animation fully completes (~18 frames at 60 fps).  Disposing before that
/// point causes `removeListener()` to throw in debug mode:
///
///   "A TextEditingController was used after being disposed."
///
/// A `double post-frame callback (~32 ms)` is **not** sufficient.
/// Use `Future.delayed(const Duration(milliseconds: 400))` instead,
/// which gives both animations time to finish before disposal.
///
/// **✅ Correct:**
/// ```dart
/// @override
/// void onClose() {
///   final ctrl = myController; // capture BEFORE super.onClose() clears state
///   WidgetsBinding.instance.addPostFrameCallback((_) {
///     try { ctrl.dispose(); } catch (_) {}
///   });
///   super.onClose(); // always AFTER scheduling the callback
/// }
/// ```
///
/// **❌ Wrong (will crash on animated exit):**
/// ```dart
/// @override
/// void onClose() {
///   myController.dispose(); // synchronous — fires BEFORE animation frame
///   super.onClose();
/// }
/// ```
///
/// ---
///
/// ## Rule 2 — One owner, one disposal path; guard with `_controllersDisposed`
///
/// Every TEC must have **exactly one** code path that calls `dispose()` on
/// it.  If both GetX's automatic `onClose()` and a parent-orchestrated
/// cleanup helper (e.g. `disposeControllers()`) exist, one must
/// **delegate** to the other.  Guard the single path with a boolean flag
/// so it is idempotent regardless of which caller fires first.
///
/// **✅ Pattern (implemented in [ItemSheetControllerBase]):**
/// ```dart
/// bool _controllersDisposed = false;
///
/// void disposeControllers() {
///   if (_controllersDisposed) return; // idempotent — safe to call N times
///   _controllersDisposed = true;
///   removeSheetListeners(); // Rule 3: remove before invalidating
///   final captured = myController;
///   WidgetsBinding.instance.addPostFrameCallback((_) {
///     try { captured.dispose(); } catch (_) {}
///   });
/// }
///
/// @override
/// void onClose() {
///   disposeControllers(); // delegate — never inline-dispose here as well
///   super.onClose();
/// }
/// ```
///
/// **What counts as a "disposal path":**
///   • Any direct call to `controller.dispose()`
///   • Any `addPostFrameCallback` that calls `controller.dispose()`
///   • Any parent form controller that invokes a cleanup helper on a child
///     item controller
///
/// If more than one of the above can fire for the same controller instance,
/// consolidate them behind the boolean guard.
///
/// ---
///
/// ## Rule 3 — Remove listeners before disposal and before re-registration
///
/// Every `controller.addListener(fn)` must be paired with a matching
/// `controller.removeListener(fn)` in **two** situations:
///
/// **a) Before disposal** — a listener that fires after its controller is
/// disposed crashes on the next notify cycle:
/// ```dart
/// void disposeControllers() {
///   if (_controllersDisposed) return;
///   _controllersDisposed = true;
///   removeSheetListeners(); // ← Rule 3: remove BEFORE scheduling dispose
///   WidgetsBinding.instance.addPostFrameCallback((_) {
///     try { myController.dispose(); } catch (_) {}
///   });
/// }
/// ```
///
/// **b) Before re-registration** — when the same GetX controller instance
/// is reused across multiple sheet sessions (see Rule 4), each call to
/// `addSheetListeners()` stacks another copy of every listener onto the
/// same TEC.  This causes redundant `validateSheet()` calls and can
/// produce state corruption and the disposed-listener crash:
/// ```dart
/// Future<void> prepareForItem({...}) async {
///   // ... field reset ...
///   removeSheetListeners(); // ← clear prior-session listeners first
///   addSheetListeners();    //   then register fresh for this session
///   snapshotState();
/// }
/// ```
///
/// ---
///
/// ## Rule 4 — Never `dispose()` TECs owned by permanent / fenix controllers
///
/// If a GetX controller is registered with `permanent: true` or
/// `fenix: true`, the **same instance** is reused across multiple usages.
/// Calling `dispose()` on its TECs between sessions makes them permanently
/// unusable — a `GetxController` does not re-run `onInit()` on fenix
/// resurrection and therefore cannot re-create the TEC.
///
/// **✅ Between sessions — reset, do NOT dispose:**
/// ```dart
/// void resetForNewSession() {
///   removeSheetListeners();
///   batchController.clear();
///   rackController.clear();
///   qtyController.clear();
///   // NO dispose() calls here
/// }
/// ```
///
/// **✅ On true final teardown (when `Get.delete()` is called explicitly):**
/// ```dart
/// @override
/// void onClose() {
///   disposeControllers(); // deferred + idempotent (Rules 1 & 2)
///   super.onClose();
/// }
/// ```
///
/// ---
///
/// ## Quick-reference checklist
///
/// Before merging any code that declares a new [TextEditingController],
/// [FocusNode], or [ScrollController], verify:
///
///   - [ ] **Rule 1** — `dispose()` is inside `addPostFrameCallback`, never
///         called synchronously in `onClose()` or any teardown method.
///   - [ ] **Rule 2** — exactly one disposal path; guarded by a `bool` flag
///         if more than one caller could trigger teardown.
///   - [ ] **Rule 3** — `removeListener` is called before `dispose()` AND
///         before any subsequent `addListener` on the same controller
///         instance (session-reset paths).
///   - [ ] **Rule 4** — if the owning [GetxController] is `permanent` /
///         `fenix`, `dispose()` is never called in the session-reset path.
///
/// ---
///
/// ## Enforcement in this codebase
///
/// | Class / Method | Rules | Implementation |
/// |---|---|---|
/// | `ItemSheetControllerBase.disposeControllers` | 1, 2, 3 | `Future.delayed(400ms)` + `_controllersDisposed` guard + `removeSheetListeners()` call |
/// | `ItemSheetControllerBase.onClose` | 2 | Delegates to `disposeControllers()`; no inline dispose |
/// | `StockEntryItemFormController.onClose` | 1 | `sourceRackController` / `targetRackController` disposed via `addPostFrameCallback` |
/// | `StockEntryItemFormController.prepareForItem` | 3 | Calls `removeSheetListeners()` before `addSheetListeners()` |
///
/// See also:
///   • `item_sheet_controller_base.dart` §§ TEC Lifecycle, disposeControllers
///   • `stock_entry_item_form_controller.dart` §§ onClose, prepareForItem
abstract final class TecLifecycleRules {
  // Private constructor — this class is a pure documentation namespace.
  // It is never instantiated.  It exists so that:
  //   1. IDE hover on `TecLifecycleRules` shows the four rules inline.
  //   2. `import … show TecLifecycleRules` makes the dependency explicit
  //      without adding any runtime overhead (tree-shaken by dart2js /
  //      flutter build --release).
  TecLifecycleRules._();
}
