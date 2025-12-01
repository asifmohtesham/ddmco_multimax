import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/auth/login_controller.dart';
import 'package:ddmco_multimax/app/modules/auth/login_screen.dart';
import 'package:ddmco_multimax/app/modules/home/home_binding.dart';
import 'package:ddmco_multimax/app/modules/home/home_screen.dart';
import 'package:ddmco_multimax/app/modules/purchase_receipt/purchase_receipt_binding.dart';
import 'package:ddmco_multimax/app/modules/purchase_receipt/purchase_receipt_screen.dart';
import 'package:ddmco_multimax/app/modules/purchase_receipt/form/purchase_receipt_form_binding.dart';
import 'package:ddmco_multimax/app/modules/purchase_receipt/form/purchase_receipt_form_screen.dart';
import 'package:ddmco_multimax/app/modules/stock_entry/stock_entry_binding.dart';
import 'package:ddmco_multimax/app/modules/stock_entry/stock_entry_screen.dart';
import 'package:ddmco_multimax/app/modules/stock_entry/form/stock_entry_form_binding.dart';
import 'package:ddmco_multimax/app/modules/stock_entry/form/stock_entry_form_screen.dart';
import 'package:ddmco_multimax/app/modules/delivery_note/delivery_note_binding.dart';
import 'package:ddmco_multimax/app/modules/delivery_note/delivery_note_screen.dart';
import 'package:ddmco_multimax/app/modules/delivery_note/form/delivery_note_form_binding.dart';
import 'package:ddmco_multimax/app/modules/delivery_note/form/delivery_note_form_screen.dart';
import 'package:ddmco_multimax/app/modules/packing_slip/packing_slip_binding.dart';
import 'package:ddmco_multimax/app/modules/packing_slip/packing_slip_screen.dart';
import 'package:ddmco_multimax/app/modules/pos_upload/pos_upload_binding.dart';
import 'package:ddmco_multimax/app/modules/pos_upload/pos_upload_screen.dart';
import 'package:ddmco_multimax/app/modules/pos_upload/form/pos_upload_form_binding.dart';
import 'package:ddmco_multimax/app/modules/pos_upload/form/pos_upload_form_screen.dart';
import 'package:ddmco_multimax/app/modules/todo/todo_binding.dart';
import 'package:ddmco_multimax/app/modules/todo/todo_screen.dart';
import 'package:ddmco_multimax/app/modules/todo/form/todo_form_screen.dart';

import 'app_routes.dart';

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
      // Add binding if ToDoFormController is created later
      transition: Transition.rightToLeftWithFade,
    ),
  ];
}
