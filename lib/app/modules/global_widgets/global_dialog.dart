import 'package:flutter/material.dart';
import 'package:get/get.dart';

// ── POS Upload error reason ─────────────────────────────────────────────────

/// Classifies why a POS Upload fetch failed so [GlobalDialog.showPosUploadError]
/// can display the most actionable message copy to the operator.
enum PosUploadErrorReason {
  /// The server returned 404 — the document name was not found.
  notFound,

  /// Any other failure: network timeout, server error, parse error, etc.
  networkError,
}

class GlobalDialog {
  /// Async confirmation bottom-sheet — resolves to [true] when the user
  /// taps the confirm button, [false] on cancel or barrier dismiss.
  ///
  /// ```dart
  /// final confirmed = await GlobalDialog.confirm(
  ///   title: 'Submit Work Order',
  ///   message: 'This will lock the document. Continue?',
  ///   confirmText: 'Submit',
  ///   confirmColor: Colors.blue,
  /// );
  /// if (confirmed != true) return;
  /// ```
  static Future<bool?> confirm({
    required String title,
    required String message,
    String confirmText = 'Confirm',
    Color confirmColor = Colors.blue,
    IconData icon = Icons.check_circle_outline,
  }) {
    return Get.bottomSheet<bool>(
      Builder(
        builder: (context) => Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: confirmColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: confirmColor, size: 32),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        child: const Text('Cancel',
                            style: TextStyle(color: Colors.black87)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: confirmColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(confirmText,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  static void showConfirmation({
    required String title,
    required String message,
    required VoidCallback onConfirm,
    String confirmText = 'Delete',
    Color confirmColor = Colors.red,
    IconData icon = Icons.delete_outline,
  }) {
    Get.bottomSheet(
      Builder(
        builder: (context) => Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: confirmColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: confirmColor, size: 32),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          side:
                              BorderSide(color: Colors.grey.shade300),
                        ),
                        child: const Text('Cancel',
                            style: TextStyle(color: Colors.black87)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onConfirm();
                        },
                        style: ElevatedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: confirmColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(confirmText,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  static void showUnsavedChanges({
    required VoidCallback onDiscard,
  }) {
    showConfirmation(
      title: 'Unsaved Changes',
      message:
          'You have unsaved changes. Are you sure you want to leave?',
      confirmText: 'Discard Changes',
      confirmColor: Colors.orange,
      icon: Icons.warning_amber_rounded,
      onConfirm: onDiscard,
    );
  }

  static void showVersionConflict({required VoidCallback onReload}) {
    Get.dialog(
      Builder(
        builder: (context) => WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            title: const Text('Version Conflict'),
            content: const Text(
              'This document has been modified by another user since you '
              'opened it.\n\nTo prevent data loss, you must reload the '
              'latest version before saving any changes.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onReload();
                },
                child: const Text('Reload Document'),
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
    );
  }

  /// Shows a bottom-sheet error modal for unrecoverable / load failures.
  ///
  /// Use this **instead of** [GlobalSnackbar.error] when the screen is
  /// empty and the user cannot proceed without taking action:
  ///
  /// ```dart
  /// GlobalDialog.showError(
  ///   title: 'Could not load Stock Entry',
  ///   message: 'Check your connection and try again.',
  ///   onRetry: fetchStockEntry,
  /// );
  /// ```
  ///
  /// When [onRetry] is null the sheet shows only a **Close** button.
  static void showError({
    required String title,
    required String message,
    VoidCallback? onRetry,
  }) {
    Get.bottomSheet(
      Builder(
        builder: (context) => Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.error_outline,
                      color: Colors.red, size: 32),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 24),
                if (onRetry != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(12)),
                            side: BorderSide(
                                color: Colors.grey.shade300),
                          ),
                          child: const Text('Close',
                              style:
                                  TextStyle(color: Colors.black87)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            onRetry();
                          },
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Retry',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side:
                            BorderSide(color: Colors.grey.shade300),
                      ),
                      child: const Text('Close',
                          style: TextStyle(color: Colors.black87)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
    );
  }

  /// Shows a bottom-sheet when a POS Upload document cannot be fetched.
  ///
  /// The [reason] drives the message copy:
  /// - [PosUploadErrorReason.notFound]     → 404: document missing / renamed
  /// - [PosUploadErrorReason.networkError] → connectivity / unexpected error
  ///
  /// Two-button layout:
  ///   • **Continue without POS** – dismisses; the SE opens without POS
  ///     context (serial dropdown will not appear).
  ///   • **Retry** (shown only when [onRetry] is supplied) – dismisses then
  ///     re-fires the fetch.
  ///
  /// Amber palette signals a recoverable warning, not a hard block —
  /// the Stock Entry document itself remains accessible.
  ///
  /// ```dart
  /// GlobalDialog.showPosUploadError(
  ///   posId:   'KX-2O25-5963-1',
  ///   reason:  PosUploadErrorReason.notFound,
  ///   onRetry: () => fetchPosUpload(posId),
  /// );
  /// ```
  static void showPosUploadError({
    required String posId,
    required PosUploadErrorReason reason,
    VoidCallback? onRetry,
  }) {
    final String title;
    final String body;
    final String hint;

    switch (reason) {
      case PosUploadErrorReason.notFound:
        title = 'POS Upload Not Found';
        body  = 'The reference "$posId" was not found on the server.';
        hint  = 'It may have been deleted, renamed, or the reference '
                'number may contain a typo. You can continue and the '
                'invoice serial selector will not be available.';
        break;
      case PosUploadErrorReason.networkError:
        title = 'Could Not Load POS Upload';
        body  = 'A connection error occurred while fetching "$posId".';
        hint  = 'Check your network and tap Retry, or continue without '
                'POS context — the invoice serial selector will not be '
                'available until the document is loaded.';
        break;
    }

    Get.bottomSheet(
      Builder(
        builder: (context) => Container(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Icon ──────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.receipt_long_outlined,
                    color: Colors.amber,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Title ─────────────────────────────────────────────────
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // ── Primary message ───────────────────────────────────────
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),

                // ── Hint / explanation ────────────────────────────────────
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),

                // ── Reference token chip ──────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tag,
                          size: 14, color: Colors.grey.shade500),
                      const SizedBox(width: 6),
                      Text(
                        posId,
                        style: TextStyle(
                          fontFamily: 'ShureTechMono',
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Action buttons ────────────────────────────────────────
                if (onRetry != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            side: BorderSide(
                                color: Colors.grey.shade300),
                          ),
                          child: const Text(
                            'Continue without POS',
                            style: TextStyle(
                                color: Colors.black87, fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            onRetry();
                          },
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text(
                            'Retry',
                            style: TextStyle(
                                fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            backgroundColor: Colors.amber.shade700,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: const Text(
                        'Continue without POS',
                        style: TextStyle(color: Colors.black87),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
    );
  }

  /// Shows a hard-block bottom-sheet when a scan would exceed the POS
  /// Upload qty cap for the selected Invoice Serial Number.
  ///
  /// Displays three stat columns — Allowed / Scanned / Remaining — so
  /// the operator immediately understands where they stand without
  /// needing to navigate away from the scan screen.
  ///
  /// ```dart
  /// GlobalDialog.showQtyCapExceeded(
  ///   serialNo:   3,
  ///   itemName:   'Widget A',
  ///   scannedQty: 5.0,
  ///   capQty:     5.0,
  /// );
  /// ```
  static void showQtyCapExceeded({
    required int    serialNo,
    required String itemName,
    required double scannedQty,
    required double capQty,
  }) {
    Get.bottomSheet(
      Builder(
        builder: (context) {
          final remaining = (capQty - scannedQty).clamp(0.0, capQty);
          final isFulfilled = remaining <= 0;
          final remainingColor =
              isFulfilled ? Colors.red.shade600 : Colors.green.shade600;

          return Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Icon ────────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.block_outlined,
                      color: Colors.orange,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Title ────────────────────────────────────────────────
                  const Text(
                    'Qty Cap Exceeded',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),

                  // ── Serial + item name ───────────────────────────────────
                  Text(
                    'Invoice Serial #$serialNo',
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    itemName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 16),

                  // ── 3-column data row ────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _dialogStatColumn(
                          'Allowed',
                          '${_fmtQty(capQty)} pcs',
                          Colors.grey.shade700,
                        ),
                        Container(
                          width: 1,
                          height: 32,
                          color: Colors.grey.shade300,
                        ),
                        _dialogStatColumn(
                          'Scanned',
                          '${_fmtQty(scannedQty)} pcs',
                          Colors.orange.shade700,
                        ),
                        Container(
                          width: 1,
                          height: 32,
                          color: Colors.grey.shade300,
                        ),
                        _dialogStatColumn(
                          'Remaining',
                          '${_fmtQty(remaining)} pcs',
                          remainingColor,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Contextual hint ──────────────────────────────────────
                  Text(
                    isFulfilled
                        ? 'This serial is fully fulfilled. No more units can be added.'
                        : 'You can still scan ${_fmtQty(remaining)} more unit(s) for this serial.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 24),

                  // ── Dismiss button ───────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text(
                        'Got It',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static Widget _dialogStatColumn(
      String label, String value, Color valueColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFamily: 'ShureTechMono',
            color: valueColor,
          ),
        ),
      ],
    );
  }

  static String _fmtQty(double q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2);
}
