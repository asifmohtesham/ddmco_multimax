import 'package:flutter/material.dart';

class ToDoFormScreen extends StatelessWidget {
  const ToDoFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ToDo Form')),
      body: const Center(child: Text('ToDo Form Content')),
    );
  }
}
