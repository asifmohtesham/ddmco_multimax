abstract class AppRoutes {
  static const LOGIN = '/login';
  static const HOME = '/home';
  static const PROFILE = _Paths.PROFILE;
  static const PURCHASE_RECEIPT = _Paths.PURCHASE_RECEIPT;
  static const PURCHASE_RECEIPT_FORM = _Paths.PURCHASE_RECEIPT_FORM;
  static const PURCHASE_ORDER = _Paths.PURCHASE_ORDER; // Added
  static const PURCHASE_ORDER_FORM = _Paths.PURCHASE_ORDER_FORM; // Added
  static const STOCK_ENTRY = _Paths.STOCK_ENTRY;
  static const STOCK_ENTRY_FORM = _Paths.STOCK_ENTRY_FORM;
  static const DELIVERY_NOTE = _Paths.DELIVERY_NOTE;
  static const DELIVERY_NOTE_FORM = _Paths.DELIVERY_NOTE_FORM;
  static const PACKING_SLIP = _Paths.PACKING_SLIP;
  static const PACKING_SLIP_FORM = _Paths.PACKING_SLIP_FORM;
  static const POS_UPLOAD = _Paths.POS_UPLOAD;
  static const POS_UPLOAD_FORM = _Paths.POS_UPLOAD_FORM;
  static const TODO = _Paths.TODO;
  static const TODO_FORM = _Paths.TODO_FORM;
  static const ITEM = _Paths.ITEM;
  static const ITEM_FORM = _Paths.ITEM_FORM;
}

abstract class _Paths {
  static const PROFILE = '/profile';
  static const PURCHASE_RECEIPT = '/purchase-receipt';
  static const PURCHASE_RECEIPT_FORM = '/purchase-receipt/form';
  static const PURCHASE_ORDER = '/purchase-order'; // Added
  static const PURCHASE_ORDER_FORM = '/purchase-order/form'; // Added
  static const STOCK_ENTRY = '/stock-entry';
  static const STOCK_ENTRY_FORM = '/stock-entry/form';
  static const DELIVERY_NOTE = '/delivery-note';
  static const DELIVERY_NOTE_FORM = '/delivery-note/form';
  static const PACKING_SLIP = '/packing-slip';
  static const PACKING_SLIP_FORM = '/packing-slip/form';
  static const POS_UPLOAD = '/pos-upload';
  static const POS_UPLOAD_FORM = '/pos-upload/form';
  static const TODO = '/todo';
  static const TODO_FORM = '/todo/form';
  static const ITEM = '/item';
  static const ITEM_FORM = '/item/form';
}