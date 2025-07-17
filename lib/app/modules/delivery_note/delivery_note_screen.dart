import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/delivery_note/delivery_note_controller.dart';

class DeliveryNoteScreen extends GetView<DeliveryNoteController> {
  const DeliveryNoteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center( // Content will be shown within the HomeScreen's Scaffold
      child: Text(
        'Delivery Note Screen Content',
        style: TextStyle(fontSize: 20),
      ),
    );
  }
}
