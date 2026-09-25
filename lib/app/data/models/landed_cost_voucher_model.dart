class LandedCostVoucher {
  final String name;
  final String? owner;
  final String creation;
  final String modified;
  final String status;
  final int docstatus;
  final String company;
  final String postingDate;
  final String distributeChargesBasedOn;
  final double totalTaxesAndCharges;
  final double? totalVendorInvoicesCost;
  final List<LandedCostPurchaseReceipt> purchaseReceipts;
  final List<LandedCostItem> items;
  final List<LandedCostTaxesAndCharges> taxes;
  final List<LandedCostVendorInvoice>? vendorInvoices;

  LandedCostVoucher({
    required this.name,
    required this.owner,
    required this.creation,
    required this.modified,
    required this.status,
    required this.docstatus,
    required this.company,
    required this.postingDate,
    required this.distributeChargesBasedOn,
    required this.totalTaxesAndCharges,
    this.totalVendorInvoicesCost,
    required this.purchaseReceipts,
    required this.items,
    required this.taxes,
    this.vendorInvoices,
  });

  factory LandedCostVoucher.fromJson(Map<String, dynamic> json) {
    var prList = json['purchase_receipts'] as List? ?? [];
    List<LandedCostPurchaseReceipt> purchaseReceipts = prList
        .map((i) => LandedCostPurchaseReceipt.fromJson(i))
        .toList();

    var itemsList = json['items'] as List? ?? [];
    List<LandedCostItem> items = itemsList
        .map((i) => LandedCostItem.fromJson(i))
        .toList();

    var taxesList = json['taxes'] as List? ?? [];
    List<LandedCostTaxesAndCharges> taxes = taxesList
        .map((i) => LandedCostTaxesAndCharges.fromJson(i))
        .toList();

    var vendorInvoicesList = json['vendor_invoices'] as List?;
    List<LandedCostVendorInvoice>? vendorInvoices;
    if (vendorInvoicesList != null) {
      vendorInvoices = vendorInvoicesList
          .map((i) => LandedCostVendorInvoice.fromJson(i))
          .toList();
    }

    return LandedCostVoucher(
      name: json['name'] ?? '',
      owner: json['owner'] ?? '',
      creation: json['creation'] ?? DateTime.now().toString(),
      modified: json['modified'] ?? '',
      status: json['status'] ?? 'Draft',
      docstatus: json['docstatus'] as int? ?? 0,
      company: json['company'] ?? '',
      postingDate: json['posting_date'] ?? '',
      distributeChargesBasedOn: json['distribute_charges_based_on'] ?? 'Qty',
      totalTaxesAndCharges:
          (json['total_taxes_and_charges'] as num?)?.toDouble() ?? 0.0,
      totalVendorInvoicesCost: (json['total_vendor_invoices_cost'] as num?)
          ?.toDouble(),
      purchaseReceipts: purchaseReceipts,
      items: items,
      taxes: taxes,
      vendorInvoices: vendorInvoices,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'company': company,
      'posting_date': postingDate,
      'distribute_charges_based_on': distributeChargesBasedOn,
      'total_taxes_and_charges': totalTaxesAndCharges,
      'purchase_receipts': purchaseReceipts.map((v) => v.toJson()).toList(),
      'items': items.map((v) => v.toJson()).toList(),
      'taxes': taxes.map((v) => v.toJson()).toList(),
    };

    if (totalVendorInvoicesCost != null) {
      data['total_vendor_invoices_cost'] = totalVendorInvoicesCost;
    }

    if (vendorInvoices != null) {
      data['vendor_invoices'] = vendorInvoices!.map((v) => v.toJson()).toList();
    }

    if (name.isNotEmpty && !name.startsWith('local_')) {
      data['name'] = name;
    }

    return data;
  }
}

class LandedCostPurchaseReceipt {
  final String? name;
  final String receiptDocumentType;
  final String receiptDocument;
  final String? supplier;
  final String? postingDate;
  final double grandTotal;

  LandedCostPurchaseReceipt({
    this.name,
    required this.receiptDocumentType,
    required this.receiptDocument,
    this.supplier,
    this.postingDate,
    required this.grandTotal,
  });

  factory LandedCostPurchaseReceipt.fromJson(Map<String, dynamic> json) {
    return LandedCostPurchaseReceipt(
      name: json['name'],
      receiptDocumentType: json['receipt_document_type'] ?? '',
      receiptDocument: json['receipt_document'] ?? '',
      supplier: json['supplier'],
      postingDate: json['posting_date'],
      grandTotal: (json['grand_total'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'receipt_document_type': receiptDocumentType,
      'receipt_document': receiptDocument,
      'grand_total': grandTotal,
    };
    if (supplier != null) data['supplier'] = supplier;
    if (postingDate != null) data['posting_date'] = postingDate;
    if (name != null && !name!.startsWith('local_')) {
      data['name'] = name;
    }
    return data;
  }
}

class LandedCostItem {
  final String? name;
  final String itemCode;
  final String? description;
  final String receiptDocumentType;
  final String receiptDocument;
  final double qty;
  final double rate;
  final double amount;
  final double applicableCharges;
  final String? purchaseReceiptItem;
  final String? costCenter;
  final int? isFixedAsset;

  LandedCostItem({
    this.name,
    required this.itemCode,
    this.description,
    required this.receiptDocumentType,
    required this.receiptDocument,
    required this.qty,
    required this.rate,
    required this.amount,
    required this.applicableCharges,
    this.purchaseReceiptItem,
    this.costCenter,
    this.isFixedAsset,
  });

  factory LandedCostItem.fromJson(Map<String, dynamic> json) {
    return LandedCostItem(
      name: json['name'],
      itemCode: json['item_code'] ?? '',
      description: json['description'],
      receiptDocumentType: json['receipt_document_type'] ?? '',
      receiptDocument: json['receipt_document'] ?? '',
      qty: (json['qty'] as num?)?.toDouble() ?? 0.0,
      rate: (json['rate'] as num?)?.toDouble() ?? 0.0,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      applicableCharges:
          (json['applicable_charges'] as num?)?.toDouble() ?? 0.0,
      purchaseReceiptItem: json['purchase_receipt_item'],
      costCenter: json['cost_center'],
      isFixedAsset: json['is_fixed_asset'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'item_code': itemCode,
      'receipt_document_type': receiptDocumentType,
      'receipt_document': receiptDocument,
      'qty': qty,
      'rate': rate,
      'amount': amount,
      'applicable_charges': applicableCharges,
    };
    if (description != null) data['description'] = description;
    if (purchaseReceiptItem != null)
      data['purchase_receipt_item'] = purchaseReceiptItem;
    if (costCenter != null) data['cost_center'] = costCenter;
    if (isFixedAsset != null) data['is_fixed_asset'] = isFixedAsset;
    if (name != null && !name!.startsWith('local_')) {
      data['name'] = name;
    }
    return data;
  }
}

class LandedCostTaxesAndCharges {
  final String? name;
  final String description;
  final double amount;
  final String? expenseAccount;
  final String? accountCurrency;
  final double exchangeRate;
  final double baseAmount;
  final int? hasCorrectiveCost;
  final int? hasOperatingCost;
  final String? operationId;
  final double? qty;

  LandedCostTaxesAndCharges({
    this.name,
    required this.description,
    required this.amount,
    this.expenseAccount,
    this.accountCurrency,
    required this.exchangeRate,
    required this.baseAmount,
    this.hasCorrectiveCost,
    this.hasOperatingCost,
    this.operationId,
    this.qty,
  });

  factory LandedCostTaxesAndCharges.fromJson(Map<String, dynamic> json) {
    return LandedCostTaxesAndCharges(
      name: json['name'],
      description: json['description'] ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      expenseAccount: json['expense_account'],
      accountCurrency: json['account_currency'],
      exchangeRate: (json['exchange_rate'] as num?)?.toDouble() ?? 1.0,
      baseAmount: (json['base_amount'] as num?)?.toDouble() ?? 0.0,
      hasCorrectiveCost: json['has_corrective_cost'] as int?,
      hasOperatingCost: json['has_operating_cost'] as int?,
      operationId: json['operation_id'],
      qty: (json['qty'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'description': description,
      'amount': amount,
      'exchange_rate': exchangeRate,
      'base_amount': baseAmount,
    };
    if (expenseAccount != null) data['expense_account'] = expenseAccount;
    if (accountCurrency != null) data['account_currency'] = accountCurrency;
    if (hasCorrectiveCost != null)
      data['has_corrective_cost'] = hasCorrectiveCost;
    if (hasOperatingCost != null) data['has_operating_cost'] = hasOperatingCost;
    if (operationId != null) data['operation_id'] = operationId;
    if (qty != null) data['qty'] = qty;
    if (name != null && !name!.startsWith('local_')) {
      data['name'] = name;
    }
    return data;
  }
}

class LandedCostVendorInvoice {
  final String? name;
  final String vendorInvoice;
  final double amount;

  LandedCostVendorInvoice({
    this.name,
    required this.vendorInvoice,
    required this.amount,
  });

  factory LandedCostVendorInvoice.fromJson(Map<String, dynamic> json) {
    return LandedCostVendorInvoice(
      name: json['name'],
      vendorInvoice: json['vendor_invoice'] ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'vendor_invoice': vendorInvoice,
      'amount': amount,
    };
    if (name != null && !name!.startsWith('local_')) {
      data['name'] = name;
    }
    return data;
  }
}
