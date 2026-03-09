# Manufacturing Module - Integration Guide

## 🚀 Quick Start

This guide walks you through integrating the Manufacturing module into your existing Multimax app.

---

## 📋 Prerequisites

### ERPNext Setup
- ✅ ERPNext v14 or higher
- ✅ Manufacturing module enabled
- ✅ API access configured
- ✅ SSL certificate (for production)

### App Requirements
- ✅ Flutter 3.0+
- ✅ GetX state management
- ✅ Existing ERPNext provider
- ✅ Internet connectivity

---

## 🔧 Step 1: ERPNext Configuration

### 1.1 Enable Manufacturing Module

```bash
# SSH into ERPNext server
bench --site [your-site] install-app erpnext

# Enable manufacturing
bench --site [your-site] set-config manufacturing 1
```

### 1.2 Create Workstations

**In ERPNext UI:**
1. Go to: **Manufacturing → Workstation → New**
2. Create workstations:
   ```
   - WS-CUTTING-01 (Cutting Station)
   - WS-WELDING-01 (Welding Station)
   - WS-PAINTING-01 (Painting Station)
   - WS-ASSEMBLY-01 (Assembly Station)
   ```

### 1.3 Create Sample BOM

**Test BOM:**
```
Item: FINISHED-PRODUCT-001
Quantity: 1

Materials:
- RAW-MAT-001 | Qty: 2 | Rate: 100
- RAW-MAT-002 | Qty: 1 | Rate: 200

Operations:
- Cutting | Workstation: WS-CUTTING-01 | Time: 30 mins
- Welding | Workstation: WS-WELDING-01 | Time: 45 mins
```

### 1.4 Configure API Access

**Create API User:**
```python
# In ERPNext Console
user = frappe.new_doc('User')
user.email = 'manufacturing_app@company.com'
user.first_name = 'Manufacturing'
user.last_name = 'App'
user.append('roles', {'role': 'Manufacturing Manager'})
user.save()

# Generate keys
api_key = frappe.generate_hash(length=20)
api_secret = frappe.generate_hash(length=40)
user.api_key = api_key
user.api_secret = api_secret
user.save()

print(f"API Key: {api_key}")
print(f"API Secret: {api_secret}")
```

---

## 📱 Step 2: App Integration

### 2.1 Add Dependencies

**pubspec.yaml:**
```yaml
dependencies:
  get: ^4.6.5
  percent_indicator: ^4.2.2  # For progress bars
  # ... existing dependencies
```

Run:
```bash
flutter pub get
```

### 2.2 Copy Manufacturing Module

The manufacturing module is in the `manufacturing` branch. Merge it:

```bash
git checkout master
git merge manufacturing
```

Or copy files manually:
```
lib/app/modules/manufacturing/
├── models/
│   ├── bom_model.dart
│   ├── work_order_model.dart
│   └── job_card_model.dart
├── bom/
│   ├── bom_controller.dart
│   ├── bom_binding.dart
│   └── bom_screen.dart
├── work_order/
│   ├── work_order_controller.dart
│   ├── work_order_binding.dart
│   └── work_order_screen.dart
└── job_card/
    ├── job_card_controller.dart
    ├── job_card_binding.dart
    └── job_card_screen.dart
```

### 2.3 Update Routes

**lib/app/routes/app_pages.dart:**

```dart
import 'package:multimax/app/modules/manufacturing/bom/bom_binding.dart';
import 'package:multimax/app/modules/manufacturing/bom/bom_screen.dart';
import 'package:multimax/app/modules/manufacturing/work_order/work_order_binding.dart';
import 'package:multimax/app/modules/manufacturing/work_order/work_order_screen.dart';
import 'package:multimax/app/modules/manufacturing/job_card/job_card_binding.dart';
import 'package:multimax/app/modules/manufacturing/job_card/job_card_screen.dart';

class Routes {
  static const MANUFACTURING_BOM = '/manufacturing/bom';
  static const MANUFACTURING_WORK_ORDERS = '/manufacturing/work-orders';
  static const MANUFACTURING_JOB_CARDS = '/manufacturing/job-cards';
}

class AppPages {
  static final routes = [
    // ... existing routes ...
    
    GetPage(
      name: Routes.MANUFACTURING_BOM,
      page: () => const BomScreen(),
      binding: BomBinding(),
    ),
    GetPage(
      name: Routes.MANUFACTURING_WORK_ORDERS,
      page: () => const WorkOrderScreen(),
      binding: WorkOrderBinding(),
    ),
    GetPage(
      name: Routes.MANUFACTURING_JOB_CARDS,
      page: () => const JobCardScreen(),
      binding: JobCardBinding(),
    ),
  ];
}
```

### 2.4 Add to Navigation Menu

**Option A: Drawer Menu**

```dart
// In your drawer widget
ListTile(
  leading: Icon(Icons.factory),
  title: Text('Manufacturing'),
  children: [
    ListTile(
      title: Text('Bill of Materials'),
      onTap: () => Get.toNamed(Routes.MANUFACTURING_BOM),
    ),
    ListTile(
      title: Text('Work Orders'),
      onTap: () => Get.toNamed(Routes.MANUFACTURING_WORK_ORDERS),
    ),
    ListTile(
      title: Text('Job Cards'),
      onTap: () => Get.toNamed(Routes.MANUFACTURING_JOB_CARDS),
    ),
  ],
),
```

**Option B: Dashboard Cards**

Use the provided `ManufacturingDashboardCards` widget:

```dart
// In home screen
import 'package:multimax/app/modules/home/widgets/manufacturing_menu_section.dart';

@override
Widget build(BuildContext context) {
  return Column(
    children: [
      // ... other widgets ...
      ManufacturingDashboardCards(),
    ],
  );
}
```

### 2.5 Configure API Provider

Ensure your `ErpnextProvider` has these methods:

```dart
class ErpnextProvider {
  // Get list with filters
  Future<Map<String, dynamic>?> getListWithFilters({
    required String doctype,
    List<String>? fields,
    Map<String, dynamic>? filters,
    String? orderBy,
    int? limit,
  });

  // Get single document
  Future<Map<String, dynamic>?> getDoc({
    required String doctype,
    required String name,
  });

  // Update document
  Future<Map<String, dynamic>?> updateDoc({
    required String doctype,
    required String name,
    required Map<String, dynamic> data,
  });

  // Run document method
  Future<Map<String, dynamic>?> runDocMethod({
    required String doctype,
    required String name,
    required String method,
    Map<String, dynamic>? args,
  });
}
```

---

## 🧪 Step 3: Testing

### 3.1 Create Test Data in ERPNext

**Create Work Order:**
```python
# In ERPNext Console
wo = frappe.new_doc('Work Order')
wo.production_item = 'FINISHED-PRODUCT-001'
wo.bom_no = 'BOM-FINISHED-PRODUCT-001-001'
wo.qty = 100
wo.company = 'Your Company'
wo.fg_warehouse = 'Finished Goods - YC'
wo.wip_warehouse = 'Work In Progress - YC'
wo.save()
wo.submit()

print(f"Work Order Created: {wo.name}")
```

**Create Job Cards:**
```python
# Job cards are auto-created when Work Order is submitted
# Or create manually:
jc = frappe.new_doc('Job Card')
jc.work_order = wo.name
jc.operation = 'Cutting'
jc.workstation = 'WS-CUTTING-01'
jc.for_quantity = 100
jc.save()

print(f"Job Card Created: {jc.name}")
```

### 3.2 Test in App

**Test Checklist:**

1. **BOM Screen**
   ```
   ✅ Navigate to BOM screen
   ✅ See list of BOMs
   ✅ Tap BOM to see details
   ✅ View materials list
   ✅ View operations list
   ✅ See cost breakdown
   ✅ Search functionality works
   ```

2. **Work Order Screen**
   ```
   ✅ Navigate to Work Orders
   ✅ See list of work orders
   ✅ Tap to see details
   ✅ Start production button works
   ✅ Progress updates correctly
   ✅ Material status shows
   ✅ Operations list displays
   ```

3. **Job Card Screen**
   ```
   ✅ Navigate to Job Cards
   ✅ See assigned job cards
   ✅ Tap card to open
   ✅ START button works
   ✅ Timer starts and counts
   ✅ PAUSE button stops timer
   ✅ Add quantity works
   ✅ Progress updates
   ✅ COMPLETE button finishes job
   ```

### 3.3 Test Error Handling

**Test Cases:**
```
❌ Test: No internet connection
   Expected: Show "No connection" message

❌ Test: Invalid API key
   Expected: Show authentication error

❌ Test: Start already running job
   Expected: Show "Job already started" message

❌ Test: Complete job at 50%
   Expected: Disable complete button
```

---

## 🔐 Step 4: Permissions Setup

Follow the `MANUFACTURING_PERMISSIONS.md` guide to:

1. Create user roles
2. Configure DocType permissions
3. Set up user-specific filters
4. Test access control

---

## 🎨 Step 5: Customization (Optional)

### Change Colors

```dart
// In screen files, find:
color: Colors.green

// Replace with your brand color:
color: Theme.of(context).primaryColor
```

### Adjust Button Sizes

```dart
// Current: 72dp height
SizedBox(
  height: 72,
  child: ElevatedButton(...),
)

// Adjust as needed:
SizedBox(
  height: 60,  // Smaller
  child: ElevatedButton(...),
)
```

### Add Translations

Use GetX translations:
```dart
Text('START WORK'.tr)

// Add to translations file:
'START WORK': 'بدء العمل',  // Arabic
'START WORK': 'शुरू करो',    // Hindi
```

---

## 📊 Step 6: Production Deployment

### Pre-Deployment Checklist

- [ ] All tests passing
- [ ] Permissions configured
- [ ] API keys secured (not in code)
- [ ] SSL enabled on ERPNext
- [ ] Error tracking configured
- [ ] User training completed
- [ ] Backup procedures in place

### Environment Configuration

**Development:**
```dart
const API_BASE_URL = 'http://localhost:8000';
const DEBUG_MODE = true;
```

**Production:**
```dart
const API_BASE_URL = 'https://erp.yourcompany.com';
const DEBUG_MODE = false;
```

### Build Release

```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release
```

---

## 🐛 Troubleshooting

### Issue: "Failed to load job cards"

**Possible Causes:**
1. API endpoint incorrect
2. Authentication failed
3. No job cards exist
4. Permission denied

**Debug:**
```dart
// Add logging in controller
print('API Response: $response');
print('Error: $e');
```

### Issue: Timer not updating

**Solution:**
```dart
// Check timer initialization
if (widget.jobCard.hasActiveTimeLog) {
  _startTimer();  // Ensure this is called
}
```

### Issue: Progress bar stuck

**Solution:**
```dart
// Force refresh
await controller.fetchJobCards();
```

---

## 📚 Additional Resources

- [Manufacturing MVP README](./MANUFACTURING_MVP_README.md) - User guide
- [Permissions Guide](./MANUFACTURING_PERMISSIONS.md) - Security setup
- [ERPNext Manufacturing Docs](https://docs.erpnext.com/docs/user/manual/en/manufacturing)
- [GetX Documentation](https://pub.dev/packages/get)

---

## ✅ Integration Complete!

You should now have:
- ✅ Manufacturing module integrated
- ✅ Routes configured
- ✅ Navigation menu added
- ✅ Permissions set up
- ✅ Testing completed
- ✅ Ready for production floor use

**Next Steps:**
1. Train production staff using the [User Guide](./MANUFACTURING_MVP_README.md)
2. Monitor usage and gather feedback
3. Adjust UI/permissions as needed
4. Add custom features if required

---

**Need Help?** Check the troubleshooting section or review ERPNext logs.