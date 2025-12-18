import 'package:multimax/app/modules/bom/bom_binding.dart';
import 'package:multimax/app/modules/bom/bom_screen.dart';
import 'package:multimax/app/modules/job_card/job_card_binding.dart';
import 'package:multimax/app/modules/job_card/job_card_screen.dart';
import 'package:multimax/app/modules/material_request/form/material_request_form_binding.dart';
import 'package:multimax/app/modules/material_request/form/material_request_form_screen.dart';
import 'package:multimax/app/modules/work_order/work_order_binding.dart';
import 'package:multimax/app/modules/work_order/work_order_screen.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/auth/login_controller.dart';
import 'package:multimax/app/modules/auth/login_screen.dart';
import 'package:multimax/app/modules/home/home_binding.dart';
import 'package:multimax/app/modules/home/home_screen.dart';
import 'package:multimax/app/modules/profile/user_profile_binding.dart';
import 'package:multimax/app/modules/profile/user_profile_screen.dart';
import 'package:multimax/app/modules/purchase_receipt/purchase_receipt_binding.dart';
import 'package:multimax/app/modules/purchase_receipt/purchase_receipt_screen.dart';
import 'package:multimax/app/modules/purchase_receipt/form/purchase_receipt_form_binding.dart';
import 'package:multimax/app/modules/purchase_receipt/form/purchase_receipt_form_screen.dart';
import 'package:multimax/app/modules/purchase_order/purchase_order_binding.dart'; // Added
import 'package:multimax/app/modules/purchase_order/purchase_order_screen.dart'; // Added
import 'package:multimax/app/modules/purchase_order/form/purchase_order_form_binding.dart'; // Added
import 'package:multimax/app/modules/purchase_order/form/purchase_order_form_screen.dart'; // Added
import 'package:multimax/app/modules/stock_entry/stock_entry_binding.dart';
import 'package:multimax/app/modules/stock_entry/stock_entry_screen.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_binding.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_screen.dart';
import 'package:multimax/app/modules/delivery_note/delivery_note_binding.dart';
import 'package:multimax/app/modules/delivery_note/delivery_note_screen.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_binding.dart';
import 'package:multimax/app/modules/delivery_note/form/delivery_note_form_screen.dart';
import 'package:multimax/app/modules/packing_slip/packing_slip_binding.dart';
import 'package:multimax/app/modules/packing_slip/packing_slip_screen.dart';
import 'package:multimax/app/modules/packing_slip/form/packing_slip_form_binding.dart';
import 'package:multimax/app/modules/packing_slip/form/packing_slip_form_screen.dart';
import 'package:multimax/app/modules/pos_upload/pos_upload_binding.dart';
import 'package:multimax/app/modules/pos_upload/pos_upload_screen.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_binding.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_screen.dart';
import 'package:multimax/app/modules/todo/todo_binding.dart';
import 'package:multimax/app/modules/todo/todo_screen.dart';
import 'package:multimax/app/modules/todo/form/todo_form_screen.dart';
import 'package:multimax/app/modules/item/item_binding.dart';
import 'package:multimax/app/modules/item/item_screen.dart';
import 'package:multimax/app/modules/item/form/item_form_binding.dart';
import 'package:multimax/app/modules/item/form/item_form_screen.dart';
import 'app_routes.dart';
import 'package:multimax/app/modules/batch/batch_binding.dart';
import 'package:multimax/app/modules/batch/batch_screen.dart';
import 'package:multimax/app/modules/batch/form/batch_form_binding.dart';
import 'package:multimax/app/modules/batch/form/batch_form_screen.dart';
import 'package:multimax/app/modules/material_request/material_request_binding.dart';
import 'package:multimax/app/modules/material_request/material_request_screen.dart';
import 'package:multimax/app/modules/material_request/material_request_binding.dart';
import 'package:multimax/app/modules/material_request/material_request_screen.dart';

class AppPages {
  static const INITIAL = AppRoutes.LOGIN;

  static final routes = [
    GetPage(
      name: AppRoutes.LOGIN,
      page: () => const LoginScreen(),
      binding: BindingsBuilder(() {
        Get.lazyPut<LoginController>(() => LoginController());
      }),
    ),
    GetPage(
      name: AppRoutes.HOME,
      page: () => const HomeScreen(),
      binding: HomeBinding(),
    ),
    GetPage(
      name: AppRoutes.PROFILE,
      page: () => const UserProfileScreen(),
      binding: UserProfileBinding(),
      transition: Transition.rightToLeft,
    ),
    GetPage(
      name: AppRoutes.PURCHASE_ORDER,
      page: () => const PurchaseOrderScreen(),
      binding: PurchaseOrderBinding(),
    ),
    GetPage(
      name: AppRoutes.PURCHASE_ORDER_FORM,
      page: () => const PurchaseOrderFormScreen(),
      binding: PurchaseOrderFormBinding(),
      transition: Transition.rightToLeftWithFade,
    ),
    GetPage(
      name: AppRoutes.PURCHASE_RECEIPT,
      page: () => PurchaseReceiptScreen(),
      binding: PurchaseReceiptBinding(),
    ),
    GetPage(
      name: AppRoutes.PURCHASE_RECEIPT_FORM,
      page: () => const PurchaseReceiptFormScreen(),
      binding: PurchaseReceiptFormBinding(),
      transition: Transition.rightToLeftWithFade,
    ),
    GetPage(
      name: AppRoutes.STOCK_ENTRY,
      page: () => const StockEntryScreen(),
      binding: StockEntryBinding(),
    ),
    GetPage(
      name: AppRoutes.STOCK_ENTRY_FORM,
      page: () => const StockEntryFormScreen(),
      binding: StockEntryFormBinding(),
      transition: Transition.rightToLeftWithFade,
    ),
    GetPage(
      name: AppRoutes.DELIVERY_NOTE,
      page: () => const DeliveryNoteScreen(),
      binding: DeliveryNoteBinding(),
    ),
    GetPage(
      name: AppRoutes.DELIVERY_NOTE_FORM,
      page: () => const DeliveryNoteFormScreen(),
      binding: DeliveryNoteFormBinding(),
      transition: Transition.rightToLeftWithFade,
    ),
    GetPage(
      name: AppRoutes.PACKING_SLIP,
      page: () => const PackingSlipScreen(),
      binding: PackingSlipBinding(),
    ),
    GetPage(
      name: AppRoutes.PACKING_SLIP_FORM,
      page: () => const PackingSlipFormScreen(),
      binding: PackingSlipFormBinding(),
      transition: Transition.rightToLeftWithFade,
    ),
    GetPage(
      name: AppRoutes.POS_UPLOAD,
      page: () => const PosUploadScreen(),
      binding: PosUploadBinding(),
    ),
    GetPage(
      name: AppRoutes.POS_UPLOAD_FORM,
      page: () => const PosUploadFormScreen(),
      binding: PosUploadFormBinding(),
      transition: Transition.rightToLeftWithFade,
    ),
    GetPage(
      name: AppRoutes.TODO,
      page: () => const ToDoScreen(),
      binding: ToDoBinding(),
    ),
    GetPage(
      name: AppRoutes.TODO_FORM,
      page: () => const ToDoFormScreen(),
      transition: Transition.rightToLeftWithFade,
    ),
    GetPage(
      name: AppRoutes.ITEM,
      page: () => const ItemScreen(),
      binding: ItemBinding(),
    ),
    GetPage(
      name: AppRoutes.ITEM_FORM,
      page: () => const ItemFormScreen(),
      binding: ItemFormBinding(),
      transition: Transition.rightToLeftWithFade,
    ),
    GetPage(
      name: AppRoutes.BOM,
      page: () => const BomScreen(),
      binding: BomBinding(),
    ),
    GetPage(
      name: AppRoutes.WORK_ORDER,
      page: () => const WorkOrderScreen(),
      binding: WorkOrderBinding(),
    ),
    GetPage(
      name: AppRoutes.JOB_CARD,
      page: () => const JobCardScreen(),
      binding: JobCardBinding(),
    ),
    GetPage(
      name: AppRoutes.BATCH,
      page: () => const BatchScreen(),
      binding: BatchBinding(),
    ),
    GetPage(
      name: AppRoutes.BATCH_FORM,
      page: () => const BatchFormScreen(),
      binding: BatchFormBinding(),
      transition: Transition.rightToLeftWithFade,
    ),
    GetPage(
      name: AppRoutes.MATERIAL_REQUEST,
      page: () => const MaterialRequestScreen(),
      binding: MaterialRequestBinding(),
    ),
    GetPage(
      name: AppRoutes.MATERIAL_REQUEST_FORM,
      page: () => const MaterialRequestFormScreen(),
      binding: MaterialRequestFormBinding(),
      transition: Transition.rightToLeftWithFade,
    ),
  ];
}