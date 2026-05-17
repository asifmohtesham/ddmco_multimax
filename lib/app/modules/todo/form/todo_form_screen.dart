import 'package:flutter/material.dart';
import 'package:multimax/app/modules/global_widgets/doctype_form_header.dart';

class ToDoFormScreen extends StatelessWidget {
  const ToDoFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const DocTypeFormHeader(title: 'ToDo Form'),
          const SliverFillRemaining(
            child: Center(child: Text('ToDo Form Content')),
          ),
        ],
      ),
    );
  }
}
