import '../widget/rack_contents_card_test.dart'
    show registerRackContentsFieldsTests;
import '../widget/stock_balance_sheets_test.dart'
    show registerStockLedgerFieldsTests;
import '../widget/stock_balance_summary_total_test.dart'
    show registerStockBalanceFieldsTests;

void registerStockResultFieldsTests() {
  registerStockBalanceFieldsTests();
  registerStockLedgerFieldsTests();
  registerRackContentsFieldsTests();
}
