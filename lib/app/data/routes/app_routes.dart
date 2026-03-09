class AppRoutes {
  // Existing routes
  static const String HOME = '/home';
  static const String LOGIN = '/login';
  static const String WORK_ORDER = '/work-order';
  static const String JOB_CARD = '/job-card';
  static const String STOCK_ENTRY = '/stock-entry';
  static const String PURCHASE_RECEIPT = '/purchase-receipt';
  static const String DELIVERY_NOTE = '/delivery-note';
  static const String PACKING_SLIP = '/packing-slip';
  
  // Manufacturing routes
  static const String MANUFACTURING_HOME = '/manufacturing';
  static const String BOM_LIST = '/manufacturing/bom';
  static const String BOM_DETAIL = '/manufacturing/bom/:id';
  static const String WORK_ORDER_LIST = '/manufacturing/work-order';
  static const String WORK_ORDER_DETAIL = '/manufacturing/work-order/:id';
  static const String JOB_CARD_LIST = '/manufacturing/job-card';
  static const String JOB_CARD_DETAIL = '/manufacturing/job-card/:id';
  static const String JOB_CARD_ACTIVE = '/manufacturing/job-card-active';
}
