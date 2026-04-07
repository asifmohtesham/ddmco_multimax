// lib/app/shared/item_sheet/tec_lifecycle_rules.dart

// ════════════════════════════════════════════════════════════════════════════
// TextEditingController (TEC) Lifecycle — Project-Wide Mandatory Rules
// ════════════════════════════════════════════════════════════════════════════
//
// Every TEC in this project MUST follow the four rules below without
// exception. Violations are the ONLY cause of the class of crash:
//
//   "A TextEditingController was used after being disposed."
//
// These rules apply equally to FocusNode, ScrollController, and any other
// ChangeNotifier-backed Flutter resource whose dispose() permanently
// invalidates it.
//
// ──────────────────────────────────────────────────────────────────────────
// Rule 1 — NEVER dispose a TEC synchronously during an animated exit.
// ──────────────────────────────────────────────────────────────────────────
//
// Flutter's _AnimatedState.didUpdateWidget calls controller.addListener()
// during the layout pass of the exit frame — AFTER onClose() / dispose()
// has already run. A synchronously disposed controller is therefore dead
// before that frame commits, causing the assertion.
//
// ✅ Always defer disposal to the next frame:
//
//   @override
//   void onClose() {
//     final captured = myController; // capture BEFORE super.onClose()
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       try { captured.dispose(); } catch (_) {}
//     });
//     super.onClose();
//   }
//
// ❌ Never:
//
//   @override
//   void onClose() {
//     myController.dispose(); // synchronous — will crash on animated exit
//     super.onClose();
//   }
//
// ──────────────────────────────────────────────────────────────────────────
// Rule 2 — ONE owner, ONE disposal path — guarded against double-dispose.
// ──────────────────────────────────────────────────────────────────────────
//
// Every TEC must have exactly one disposal code path. If both onClose() and
// a public disposeControllers() method exist, one must delegate to the
// other. Use a boolean guard to make the path idempotent regardless of the
// call order (GetX lifecycle vs. parent-orchestrated cleanup).
//
// ✅ Pattern (implemented in ItemSheetControllerBase):
//
//   bool _tecDisposed = false;
//
//   void disposeControllers() {
//     if (_tecDisposed) return;   // idempotent guard
//     _tecDisposed = true;
//     final captured = myController;
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       try { captured.dispose(); } catch (_) {}
//     });
//   }
//
//   @override
//   void onClose() {
//     disposeControllers(); // delegate — never duplicate the logic
//     super.onClose();
//   }
//
// ──────────────────────────────────────────────────────────────────────────
// Rule 3 — Remove listeners BEFORE disposal and BEFORE re-registration.
// ──────────────────────────────────────────────────────────────────────────
//
// Any addListener(fn) call must be paired with a removeListener(fn) call:
//   a) before dispose(), and
//   b) before addListener is called again on the same instance in a new
//      session (e.g. when a GetX controller is reused across sheet opens).
//
// A leaked listener on a dead controller will crash on the next notify
// cycle. A duplicated listener on a live controller causes redundant
// validateSheet() calls and state corruption.
//
// ✅ On every session reset (prepareForItem / initForNewItem):
//
//   removeSheetListeners(); // clear any prior-session listeners first
//   addSheetListeners();    // then register fresh for this session
//
// ✅ On teardown (inside disposeControllers, before deferred dispose):
//
//   removeSheetListeners(); // remove all before the controller dies
//   // then schedule deferred dispose
//
// ──────────────────────────────────────────────────────────────────────────
// Rule 4 — Permanent / fenix controllers: RESET, do not dispose between
//          sessions; dispose ONLY on true final teardown.
// ──────────────────────────────────────────────────────────────────────────
//
// If a GetxController is registered with permanent: true or fenix: true,
// its TECs survive across multiple uses. Calling dispose() between sessions
// permanently invalidates them, making the second session crash immediately.
//
// ✅ Between sessions — reset, do NOT dispose:
//
//   void resetForNewSession() {
//     removeSheetListeners();
//     batchController.clear();
//     rackController.clear();
//     qtyController.clear();
//     // NO dispose() calls here
//   }
//
// ✅ On true final teardown (Get.delete is called / controller is destroyed):
//
//   @override
//   void onClose() {
//     disposeControllers(); // deferred + idempotent
//     super.onClose();
//   }
//
// ════════════════════════════════════════════════════════════════════════════
// Quick-reference checklist for every new TEC in this project
// ════════════════════════════════════════════════════════════════════════════
//
//   [ ] Declared as a final field (never re-assigned after construction)
//   [ ] dispose() is ONLY called inside disposeControllers()
//   [ ] disposeControllers() uses addPostFrameCallback (deferred)
//   [ ] disposeControllers() is guarded by a _disposed bool (idempotent)
//   [ ] onClose() delegates to disposeControllers() — no inline dispose
//   [ ] removeSheetListeners() is called before addSheetListeners() on
//       every prepareForItem / session-reset path
//   [ ] If the controller is permanent/fenix: clear() between sessions,
//       dispose() only in onClose()
//
// ════════════════════════════════════════════════════════════════════════════

// This file is documentation only — no runtime code.
// It is imported nowhere. Its Dartdoc comments are the canonical spec.
