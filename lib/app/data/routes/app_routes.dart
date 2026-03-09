abstract class AppRoutes {
  // Core routes
  static const LOGIN = '/login';
  static const HOME = '/home';
  static const ABOUT = '/about';
  
  // User routes
  static const PROFILE = _Paths.PROFILE;
  
  // Purchase routes
  static const PURCHASE_RECEIPT = _Paths.PURCHASE_RECEIPT;
  static const PURCHASE_RECEIPT_FORM = _Paths.PURCHASE_RECEIPT_FORM;
  static const PURCHASE_ORDER = _Paths.PURCHASE_ORDER;
  static const PURCHASE_ORDER_FORM = _Paths.PURCHASE_ORDER_FORM;
  
  // Stock routes
  static const STOCK_ENTRY = _Paths.STOCK_ENTRY;
  static const STOCK_ENTRY_FORM = _Paths.STOCK_ENTRY_FORM;
  
  // Delivery routes
  static const DELIVERY_NOTE = _Paths.DELIVERY_NOTE;
  static const DELIVERY_NOTE_FORM = _Paths.DELIVERY_NOTE_FORM;
  static const PACKING_SLIP = _Paths.PACKING_SLIP;
  static const PACKING_SLIP_FORM = _Paths.PACKING_SLIP_FORM;
  
  // POS routes
  static const POS_UPLOAD = _Paths.POS_UPLOAD;
  static const POS_UPLOAD_FORM = _Paths.POS_UPLOAD_FORM;
  
  // Task routes
  static const TODO = _Paths.TODO;
  static const TODO_FORM = _Paths.TODO_FORM;
  
  // Item routes
  static const ITEM = _Paths.ITEM;
  static const ITEM_FORM = _Paths.ITEM_FORM;
  
  // Manufacturing routes
  static const BOM = _Paths.BOM;
  static const WORK_ORDER = _Paths.WORK_ORDER;
  static const JOB_CARD = _Paths.JOB_CARD;
  
  // Batch routes
  static const BATCH = _Paths.BATCH;
  static const BATCH_FORM = _Paths.BATCH_FORM;
  
  // Material Request routes
  static const MATERIAL_REQUEST = _Paths.MATERIAL_REQUEST;
  static const MATERIAL_REQUEST_FORM = _Paths.MATERIAL_REQUEST_FORM;
  
  // Report routes
  static const STOCK_BALANCE_REPORT = _Paths.STOCK_BALANCE_REPORT;
  static const STOCK_LEDGER_REPORT = _Paths.STOCK_LEDGER_REPORT;
  static const BATCH_WISE_BALANCE_REPORT = _Paths.BATCH_WISE_BALANCE_REPORT;
}

abstract class _Paths {
  // User paths
  static const PROFILE = '/profile';
  
  // Purchase paths
  static const PURCHASE_RECEIPT = '/purchase-receipt';
  static const PURCHASE_RECEIPT_FORM = '/purchase-receipt/form';
  static const PURCHASE_ORDER = '/purchase-order';
  static const PURCHASE_ORDER_FORM = '/purchase-order/form';
  
  // Stock paths
  static const STOCK_ENTRY = '/stock-entry';
  static const STOCK_ENTRY_FORM = '/stock-entry/form';
  
  // Delivery paths
  static const DELIVERY_NOTE = '/delivery-note';
  static const DELIVERY_NOTE_FORM = '/delivery-note/form';
  static const PACKING_SLIP = '/packing-slip';
  static const PACKING_SLIP_FORM = '/packing-slip/form';
  
  // POS paths
  static const POS_UPLOAD = '/pos-upload';
  static const POS_UPLOAD_FORM = '/pos-upload/form';
  
  // Task paths
  static const TODO = '/todo';
  static const TODO_FORM = '/todo/form';
  
  // Item paths
  static const ITEM = '/item';
  static const ITEM_FORM = '/item/form';
  
  // Manufacturing paths
  static const BOM = '/manufacturing/bom';
  static const WORK_ORDER = '/manufacturing/work-orders';
  static const JOB_CARD = '/manufacturing/job-cards';
  
  // Batch paths
  static const BATCH = '/batch';
  static const BATCH_FORM = '/batch/form';
  
  // Material Request paths
  static const MATERIAL_REQUEST = '/material-request';
  static const MATERIAL_REQUEST_FORM = '/material-request/form';
  
  // Report paths
  static const STOCK_BALANCE_REPORT = '/stock/reports/balance';
  static const STOCK_LEDGER_REPORT = '/stock/reports/ledger';
  static const BATCH_WISE_BALANCE_REPORT = '/stock/reports/batch-wise-balance';
}
