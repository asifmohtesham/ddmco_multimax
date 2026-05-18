# StatefulWidget Audit — asifmohtesham/ddmco_multimax

## 1. StatefulWidget Inventory

### Category A: Full Screen Modules (State-managed life-cycle)
| Class | File Path | Issue Reference |
|-------|-----------|-----------------|
| JobCardScreen | lib/app/modules/job_card/job_card_screen.dart | #1, #2 |
| ToDoScreen | lib/app/modules/todo/todo_screen.dart | #1, #2 |
| PosUploadScreen | lib/app/modules/pos_upload/pos_upload_screen.dart | #1, #2 |
| WorkOrderScreen | lib/app/modules/work_order/work_order_screen.dart | #1, #2 |
| PackingSlipScreen | lib/app/modules/packing_slip/packing_slip_screen.dart | #1, #2 |
| DeliveryNoteScreen | lib/app/modules/delivery_note/delivery_note_screen.dart | #1, #2 |
| MaterialRequestScreen | lib/app/modules/material_request/material_request_screen.dart | #1, #2 |
| StockEntryScreen | lib/app/modules/stock_entry/stock_entry_screen.dart | #1, #2 |
| PurchaseReceiptScreen | lib/app/modules/purchase_receipt/purchase_receipt_screen.dart | #1, #2 |
| PurchaseOrderScreen | lib/app/modules/purchase_order/purchase_order_screen.dart | #1, #2 |
| ItemScreen | lib/app/modules/item/item_screen.dart | #1, #2 |

### Category B: Filter Bottom Sheets (Wrappers)
| Class | File Path | Issue Reference |
|-------|-----------|-----------------|
| ToDoFilterBottomSheet | lib/app/modules/todo/widgets/todo_filter_bottom_sheet.dart | #1 |
| PosUploadFilterBottomSheet | lib/app/modules/pos_upload/widgets/pos_upload_filter_bottom_sheet.dart | #1 |
| PurchaseOrderFilterBottomSheet | lib/app/modules/purchase_order/widgets/purchase_order_filter_bottom_sheet.dart | #1 |
| StockEntryFilterBottomSheet | lib/app/modules/stock_entry/widgets/stock_entry_filter_bottom_sheet.dart | #1 |
| ItemFilterBottomSheet | lib/app/modules/item/widgets/item_filter_bottom_sheet.dart | #1 |
| MaterialRequestFilterBottomSheet | lib/app/modules/material_request/widgets/material_request_filter_bottom_sheet.dart | #1 |
| PurchaseReceiptFilterBottomSheet | lib/app/modules/purchase_receipt/widgets/purchase_receipt_filter_bottom_sheet.dart | #1 |
| PackingSlipFilterBottomSheet | lib/app/modules/packing_slip/widgets/packing_slip_filter_bottom_sheet.dart | #1 |
| FilterBottomSheet | lib/app/modules/delivery_note/widgets/filter_bottom_sheet.dart | #1 |
| BatchFilterBottomSheet | lib/app/modules/batch/widgets/batch_filter_bottom_sheet.dart | #1 |

### Category C: Form Tabs & Logic Heavy Components
| Class | File Path | Issue Reference |
|-------|-----------|-----------------|
| _DetailsTab | lib/app/modules/pos_upload/form/pos_upload_form_screen.dart | #3, #5, #6 |
| _ItemsTab | lib/app/modules/pos_upload/form/pos_upload_form_screen.dart | #4, #6 |
| BarcodeInputWidget | lib/app/modules/global_widgets/barcode_input_widget.dart | - |
| WarehousePickerSheet | lib/app/modules/global_widgets/warehouse_picker_sheet.dart | #4 |

### Category D: Sanctioned (Animations/Shimmers)
| Class | File Path | Note |
|-------|-----------|------|
| _SkeletonDrawerItem | lib/app/modules/global_widgets/app_nav_drawer.dart | Vsync required for shimmer |
| _ProfileSkeleton | lib/app/modules/profile/user_profile_screen.dart | Vsync required for shimmer |
| SessionDefaultsBottomSheet | lib/app/modules/home/widgets/session_defaults_bottom_sheet.dart | Local UI state management |

---

## 2. Technical Issues Detail

### #1: Field Initialisation Search (`Get.find`)
- **Impact:** Critical. Calling `Get.find()` in the `State` field initialiser or constructor (outside `build`/`initState`) can fail if the binding hasn't finished.
- **Root Cause:** Bypasses GetX's dependency injection lifecycle guarantees.

### #2: Disconnected Scroll Lifecycle
- **Impact:** Moderate. `ScrollController` is disposed by the Widget State, but the `GetxController` (holding the data) persists.
- **Root Cause:** Lifecycle mismatch between Widget tree and GetX route stack.

### #3: Orphaned Worker Leaks (`ever`)
- **Impact:** High/Scale-Breaking. Workers registered in `initState` without `dispose()` in the State object accumulate.
- **Root Cause:** 1,000 form opens = 1,000 active listeners on the same Rx field.

### #4: `setState` vs `Obx` Conflict
- **Impact:** Moderate. Rebuilding via `setState` inside a parent `Obx` causes redundant frames and potential jank.
- **Root Cause:** Two competing reactive systems managing the same subtree.

### #5: Text Controller Sync Failure
- **Impact:** Moderate. Controllers initialised in `initState` from Rx values don't update on subsequent Rx changes (e.g. after refresh).
- **Root Cause:** State is not aware of Rx updates without explicit listeners.

### #6: Stateless `TabBar` Resets
- **Impact:** Moderate/UX. `DefaultTabController` inside a `GetView.build` resets to index 0 on every reactive rebuild.
- **Root Cause:** Lack of persistent state for the Tab controller.

---

## 3. Scalability & Release Assessment

### Use Case Table
| Scenario | Load / Volume | Advisability |
|----------|---------------|--------------|
| Light Testing | < 50 scans/day | Safe |
| Standard Ops | 100-500 scans/day | Risky (Accumulated leaks) |
| High Throughput | 1,000+ scans/day | **DO NOT RELEASE** (O(n²) lookups + memory leaks) |

### Prioritised Migration Plan
1. **Critical (Worker Cleanup):** Fix `_DetailsTab` worker disposal.
2. **Critical (KPI Optimization):** Replace `indexOf` in `completedCount` (O(n²) -> O(n)).
3. **High (Lifecycle Alignment):** Move `ScrollController` to GetxControllers for all Screen classes.
4. **Moderate (UX):** Lift `DefaultTabController` out of the `Obx` scope.
