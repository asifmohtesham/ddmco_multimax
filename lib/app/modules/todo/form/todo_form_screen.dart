import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';

class ToDoFormScreen extends StatelessWidget {
  const ToDoFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MainAppBar(title: 'ToDo Form'),
      body: const Center(child: Text('ToDo Form Content')),
    );
  }
}
