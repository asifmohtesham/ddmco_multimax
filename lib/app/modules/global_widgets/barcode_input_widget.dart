import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';

class BarcodeInputWidget extends StatefulWidget {
  final TextEditingController? controller;
  final Function(String) onScan;
  final bool isLoading;
  final bool isSuccess;
  final bool hasError;
  final String hintText;
  final String? activeRoute;
  final bool isEmbedded;

  const BarcodeInputWidget({
    super.key,
    required this.onScan,
    this.controller,
    this.isLoading = false,
    this.isSuccess = false,
    this.hasError = false,
    this.hintText = 'Scan or enter barcode',
    this.activeRoute,
    this.isEmbedded = false,
  });

  @override
  State<BarcodeInputWidget> createState() => _BarcodeInputWidgetState();
}

class _BarcodeInputWidgetState extends State<BarcodeInputWidget> {
  late TextEditingController _textController;
  final DataWedgeService _dataWedgeService = Get.find<DataWedgeService>();
  Worker? _scanWorker;

  @override
  void initState() {
    super.initState();
    _textController = widget.controller ?? TextEditingController();

    _scanWorker = ever(_dataWedgeService.scannedCode, (String code) {
      if (code.isNotEmpty) {
        if (widget.activeRoute != null &&
            Get.currentRoute != widget.activeRoute) {
          return;
        }
        final cleanCode = code.trim();
        _textController.text = cleanCode;
        _textController.selection = TextSelection.fromPosition(
          TextPosition(offset: _textController.text.length),
        );
        widget.onScan(cleanCode);
      }
    });
  }

  @override
  void dispose() {
    _scanWorker?.dispose();
    if (widget.controller == null) {
      _textController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final primaryColor = cs.primary;

    final decoration = widget.isEmbedded
        ? BoxDecoration(
            color: primaryColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: primaryColor.withValues(alpha: 0.1)),
          )
        : BoxDecoration(
            color: cs.surface,
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          );

    final padding = widget.isEmbedded
        ? const EdgeInsets.all(12.0)
        : const EdgeInsets.all(16.0);

    final inputBorder = widget.isEmbedded
        ? OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.5)),
          )
        : OutlineInputBorder(borderRadius: BorderRadius.circular(30));

    final contentPadding = widget.isEmbedded
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 14)
        : const EdgeInsets.symmetric(horizontal: 20, vertical: 0);

    // Determine helper text and semantic colour
    String? helperText = widget.hintText;
    Color? helperColor = cs.onSurface.withValues(alpha: 0.5);

    if (widget.isLoading) {
      helperText = 'Processing...';
      helperColor = cs.primary;
    } else if (widget.isSuccess) {
      helperText = 'Scan Validated';
      helperColor = cs.tertiary;
    } else if (widget.hasError) {
      helperText = 'Scan Failed';
      helperColor = cs.error;
    }

    return Container(
      padding: padding,
      decoration: decoration,
      child: SafeArea(
        bottom: !widget.isEmbedded,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.isEmbedded)
              Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: primaryColor.withValues(alpha: 0.2)),
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: Icon(Icons.qr_code_scanner,
                    color: primaryColor, size: 24),
              ),
            Expanded(
              child: TextFormField(
                controller: _textController,
                readOnly: widget.isLoading,
                decoration: InputDecoration(
                  labelText: 'Barcode',
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  helperText: helperText,
                  helperStyle: TextStyle(
                    color: helperColor,
                    fontWeight:
                        (widget.isSuccess || widget.hasError)
                            ? FontWeight.bold
                            : FontWeight.normal,
                  ),
                  labelStyle: TextStyle(
                    color: widget.isEmbedded
                        ? cs.onSurface.withValues(alpha: 0.7)
                        : null,
                    fontWeight:
                        widget.isEmbedded ? FontWeight.w500 : null,
                  ),
                  border: inputBorder,
                  enabledBorder: widget.isEmbedded
                      ? OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: widget.hasError
                                ? cs.error
                                : cs.outline.withValues(alpha: 0.0),
                          ),
                        )
                      : (widget.hasError
                          ? OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide:
                                  BorderSide(color: cs.error),
                            )
                          : null),
                  focusedBorder: widget.isEmbedded
                      ? OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: widget.hasError
                                ? cs.error
                                : primaryColor,
                            width: 1.5,
                          ),
                        )
                      : (widget.hasError
                          ? OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide(
                                  color: cs.error, width: 2),
                            )
                          : null),
                  contentPadding: contentPadding,
                  prefixIcon: widget.isEmbedded
                      ? null
                      : Icon(Icons.qr_code_scanner,
                          color: cs.onSurface.withValues(alpha: 0.5)),
                  filled: widget.isEmbedded,
                  fillColor: cs.surface,
                  suffixIcon: widget.isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5),
                          ),
                        )
                      : (widget.isSuccess
                          ? Icon(Icons.check_circle,
                              color: cs.tertiary)
                          : (widget.hasError
                              ? Icon(Icons.error, color: cs.error)
                              : IconButton(
                                  icon: Icon(
                                    widget.isEmbedded
                                        ? Icons.arrow_forward
                                        : Icons.send,
                                    color: widget.isEmbedded
                                        ? primaryColor
                                        : null,
                                  ),
                                  onPressed: () {
                                    if (_textController.text
                                        .trim()
                                        .isNotEmpty) {
                                      widget.onScan(
                                          _textController.text.trim());
                                    }
                                  },
                                ))),
                ),
                onFieldSubmitted: (value) {
                  if (value.trim().isNotEmpty && !widget.isLoading) {
                    widget.onScan(value.trim());
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
