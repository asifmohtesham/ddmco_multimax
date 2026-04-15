import 'package:flutter/material.dart';
import 'package:multimax/app/shared/item_sheet/target_rack_delegate.dart';

/// Target Rack field with picker and warehouse label.
///
/// Depends only on [TargetRackDelegate] — no awareness of source rack
/// or SE type strings. Renders identically for Manufacture FG rows,
/// Material Receipt, and any future DocType that places stock into a bin.
class SharedTargetRackField extends StatelessWidget {
  final TargetRackDelegate controller;
  const SharedTargetRackField({super.key, required this.controller});
  // ... renders ValidatedRackField + optional warehouse label
}
