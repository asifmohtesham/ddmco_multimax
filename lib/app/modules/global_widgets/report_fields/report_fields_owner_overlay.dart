import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'report_fields_controller.dart';

/// An overlay whose content belongs to the report owner that opened it.
class ReportFieldsOwnerOverlay extends StatefulWidget {
  const ReportFieldsOwnerOverlay({
    super.key,
    required this.fields,
    required this.generation,
    required this.builder,
  });

  final ReportFieldsController fields;
  final int generation;
  final WidgetBuilder builder;

  @override
  State<ReportFieldsOwnerOverlay> createState() =>
      _ReportFieldsOwnerOverlayState();
}

class _ReportFieldsOwnerOverlayState extends State<ReportFieldsOwnerOverlay> {
  late final Worker _ownerWorker;
  bool _removing = false;

  bool get _isCurrent => widget.fields.ownerGeneration == widget.generation;

  @override
  void initState() {
    super.initState();
    _ownerWorker = ever(widget.fields.state, (_) {
      if (!_isCurrent) setState(() {});
    });
  }

  @override
  void dispose() {
    _ownerWorker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isCurrent) return widget.builder(context);
    if (!_removing) {
      _removing = true;
      final route = ModalRoute.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route != null && route.isActive) route.navigator?.removeRoute(route);
      });
    }
    return const SizedBox.shrink();
  }
}
