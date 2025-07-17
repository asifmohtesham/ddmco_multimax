import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/stock_entry/stock_entry_controller.dart';

class StockEntryScreen extends GetView<StockEntryController> {
  const StockEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center( // Content will be shown within the HomeScreen's Scaffold
      child: Text(
        'Stock Entry Screen Content',
        style: TextStyle(fontSize: 20),
      ),
    );
  }
}
