## 1.1.0

### New Features

*   **Batch Management:**
    *   Introduced `BatchFormScreen` for creating and editing batches.
    *   Added ability to generate Batch IDs automatically using Item EAN and random characters.
    *   Integrated QR code and Barcode (Code128/EAN8) generation for batches with preview.
    *   Added support for exporting batch labels as PNG images and PDF vectors.
    *   Added Item and Purchase Order selection via searchable bottom sheets.

*   **POS Upload:**
    *   Added `PosUploadFormScreen` to manage POS uploads.
    *   Features include viewing upload details, updating status and totals, and searching/listing items.

*   **ToDo Management:**
    *   Added `ToDoScreen` for tracking tasks.
    *   Features include infinite scrolling, filtering (by status/name), and expandable cards for detailed views.
    *   Added HTML content support for task descriptions.

*   **Purchase Order & Material Request:**
    *   Added `PurchaseOrderFormScreen`.
    *   Enhanced `MaterialRequestScreen` and associated forms.

### Improvements

*   **UI/UX:**
    *   Added `PopScope` to forms to prevent accidental data loss (unsaved changes dialog).
    *   Integrated `AppNavDrawer` into main screens for consistent navigation.
    *   Enhanced `DeliveryNoteItemBottomSheet` with real-time batch validation, rack validation, and custom fields (Invoice Serial No).
    *   Added "ShureTechMono" font for clear barcode text rendering.

*   **General:**
    *   Updated dependencies in `pubspec.yaml` (e.g., `share_plus`, `barcode_widget`, `qr_flutter`).
    *   Various bug fixes and performance improvements.
