import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/packing_slip/packing_slip_controller.dart';

class PackingSlipScreen extends GetView<PackingSlipController> {
  const PackingSlipScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center( // Content will be shown within the HomeScreen's Scaffold
      child: Text(
        'Packing Slip Screen Content',
        style: TextStyle(fontSize: 20),
      ),
    );
  }
}
