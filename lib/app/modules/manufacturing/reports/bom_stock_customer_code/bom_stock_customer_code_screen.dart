import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/manufacturing/reports/bom_stock_customer_code/bom_stock_customer_code_controller.dart';

class BomStockCustomerCodeScreen
    extends GetView<BomStockCustomerCodeController> {
  const BomStockCustomerCodeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('BOM Stock with Customer Code')),
    );
  }
}
