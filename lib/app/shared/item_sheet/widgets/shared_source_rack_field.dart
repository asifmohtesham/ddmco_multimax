import 'package:flutter/material.dart';
import 'package:multimax/app/shared/item_sheet/source_rack_delegate.dart';

/// Source Rack field with picker, balance chip, and warehouse label.
///
/// Depends only on [SourceRackDelegate] — no awareness of target rack,
/// SE type strings, or any DocType-specific logic.
/// Drop this into any item-sheet that has a source-rack requirement.
class SharedSourceRackField extends StatelessWidget {
  final SourceRackDelegate controller;
  const SharedSourceRackField({super.key, required this.controller});
  // ... renders ValidatedRackField + BalanceChip + optional warehouse label
}
