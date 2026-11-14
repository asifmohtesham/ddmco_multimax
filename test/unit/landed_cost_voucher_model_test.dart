import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/landed_cost_voucher_model.dart';

void main() {
  // ERPNext's Landed Cost Voucher has no `status` field, so the label must
  // come from docstatus (staging returned none; the model used to say Draft).
  test('status follows docstatus when the server sends none', () {
    String statusOf(int docstatus) =>
        LandedCostVoucher.fromJson({'docstatus': docstatus}).status;
    expect(statusOf(0), 'Draft');
    expect(statusOf(1), 'Submitted');
    expect(statusOf(2), 'Cancelled');
  });
}
