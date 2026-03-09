# Manufacturing Module - Complete Setup Guide

## 📋 Table of Contents

1. [ERPNext Permissions Setup](#erpnext-permissions-setup)
2. [Route Integration](#route-integration)
3. [Dependency Injection](#dependency-injection)
4. [Navigation Menu](#navigation-menu)
5. [Testing](#testing)
6. [Troubleshooting](#troubleshooting)

---

## 🔐 ERPNext Permissions Setup

### Step 1: Create User Roles

Go to **Setup > Users and Permissions > Role** and create these roles:

#### 1. Manufacturing Manager
**Full control over all manufacturing operations**

```
Role Name: Manufacturing Manager
Description: Full access to manufacturing module
```

#### 2. Manufacturing User
**Can create and manage manufacturing documents**

```
Role Name: Manufacturing User
Description: Create and manage work orders and BOMs
```

#### 3. Supervisor
**Can view and update work orders and job cards**

```
Role Name: Supervisor
Description: Supervise production floor operations
```

#### 4. Labourer
**Limited to job card operations only**

```
Role Name: Labourer
Description: Execute job card operations on production floor
```

---

### Step 2: Configure DocType Permissions

Go to **Setup > Permissions > [DocType Name]** for each manufacturing DocType:

#### BOM Permissions

| Role | Read | Write | Create | Delete | Submit | Cancel | Print | Export |
|------|------|-------|--------|--------|--------|--------|-------|--------|
| Manufacturing Manager | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Manufacturing User | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ |
| Supervisor | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |
| Labourer | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

**ERPNext Configuration:**
```python
# Go to: Setup > Permissions > BOM
# Add permissions for each role

Manufacturing Manager: Read=1, Write=1, Create=1, Delete=1, Submit=1
Manufacturing User: Read=1, Write=1, Create=1, Submit=1
Supervisor: Read=1, Print=1, Export=1
```

#### Work Order Permissions

| Role | Read | Write | Create | Delete | Submit | Cancel | Print | Export |
|------|------|-------|--------|--------|--------|--------|-------|--------|
| Manufacturing Manager | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Manufacturing User | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| Supervisor | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |
| Labourer | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

**ERPNext Configuration:**
```python
# Go to: Setup > Permissions > Work Order

Manufacturing Manager: Read=1, Write=1, Create=1, Delete=1, Submit=1, Cancel=1
Manufacturing User: Read=1, Write=1, Create=1, Submit=1, Cancel=1
Supervisor: Read=1, Write=1, Print=1, Export=1
Labourer: Read=1
```

#### Job Card Permissions

| Role | Read | Write | Create | Delete | Submit | Cancel | Print | Export |
|------|------|-------|--------|--------|--------|--------|-------|--------|
| Manufacturing Manager | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Manufacturing User | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ |
| Supervisor | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |
| Labourer | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |

**ERPNext Configuration:**
```python
# Go to: Setup > Permissions > Job Card

Manufacturing Manager: Read=1, Write=1, Create=1, Delete=1, Submit=1, Cancel=1
Manufacturing User: Read=1, Write=1, Create=1, Submit=1
Supervisor: Read=1, Write=1, Submit=1, Print=1, Export=1
Labourer: Read=1, Write=1, Submit=1  # Can update their own job cards
```

---

### Step 3: Quick Setup Script (Optional)

Run this in ERPNext console (**Developer > Console**):

```python
import frappe

# Create roles if they don't exist
roles = [
    'Manufacturing Manager',
    'Manufacturing User',
    'Supervisor',
    'Labourer'
]

for role_name in roles:
    if not frappe.db.exists('Role', role_name):
        role = frappe.get_doc({
            'doctype': 'Role',
            'role_name': role_name,
            'desk_access': 0 if role_name == 'Labourer' else 1
        })
        role.insert()
        print(f"Created role: {role_name}")

# BOM Permissions
frappe.set_value('DocPerm', {'parent': 'BOM', 'role': 'Manufacturing Manager'}, 
                 {'read': 1, 'write': 1, 'create': 1, 'delete': 1, 'submit': 1})
frappe.set_value('DocPerm', {'parent': 'BOM', 'role': 'Manufacturing User'}, 
                 {'read': 1, 'write': 1, 'create': 1, 'submit': 1})
frappe.set_value('DocPerm', {'parent': 'BOM', 'role': 'Supervisor'}, 
                 {'read': 1})

# Work Order Permissions
frappe.set_value('DocPerm', {'parent': 'Work Order', 'role': 'Manufacturing Manager'}, 
                 {'read': 1, 'write': 1, 'create': 1, 'delete': 1, 'submit': 1, 'cancel': 1})
frappe.set_value('DocPerm', {'parent': 'Work Order', 'role': 'Manufacturing User'}, 
                 {'read': 1, 'write': 1, 'create': 1, 'submit': 1, 'cancel': 1})
frappe.set_value('DocPerm', {'parent': 'Work Order', 'role': 'Supervisor'}, 
                 {'read': 1, 'write': 1})
frappe.set_value('DocPerm', {'parent': 'Work Order', 'role': 'Labourer'}, 
                 {'read': 1})

# Job Card Permissions
frappe.set_value('DocPerm', {'parent': 'Job Card', 'role': 'Manufacturing Manager'}, 
                 {'read': 1, 'write': 1, 'create': 1, 'delete': 1, 'submit': 1, 'cancel': 1})
frappe.set_value('DocPerm', {'parent': 'Job Card', 'role': 'Manufacturing User'}, 
                 {'read': 1, 'write': 1, 'create': 1, 'submit': 1})
frappe.set_value('DocPerm', {'parent': 'Job Card', 'role': 'Supervisor'}, 
                 {'read': 1, 'write': 1, 'submit': 1})
frappe.set_value('DocPerm', {'parent': 'Job Card', 'role': 'Labourer'}, 
                 {'read': 1, 'write': 1, 'submit': 1})

frappe.db.commit()
print("Permissions configured successfully!")
```

---

### Step 4: Assign Roles to Users

Go to **Setup > Users and Permissions > User**

**For Production Floor Workers:**
```
User: john.doe@company.com
Role: Labourer
Employee: EMP-001
```

**For Floor Supervisors:**
```
User: supervisor@company.com
Roles: Supervisor, Labourer
Employee: EMP-SUPER-001
```

**For Manufacturing Managers:**
```
User: manager@company.com
Roles: Manufacturing Manager, Manufacturing User, Supervisor
Employee: EMP-MGR-001
```

---

## 🛣️ Route Integration

### Routes Are Already Configured!

The manufacturing routes are defined in:
```
lib/app/routes/manufacturing_routes.dart
```

**Available Routes:**
- `/manufacturing/bom` - Bill of Materials screen
- `/manufacturing/work-orders` - Work Orders screen
- `/manufacturing/job-cards` - Job Cards screen

### Integration into Main App

**Option 1: Add to existing app_pages.dart**

If you have a main `app_pages.dart`, import manufacturing routes:

```dart
import 'package:multimax/app/routes/manufacturing_routes.dart';

class AppPages {
  static final routes = [
    // ... existing routes
    ...ManufacturingRoutes.routes,  // Add this line
  ];
}
```

**Option 2: Direct navigation**

Navigate from anywhere in the app:

```dart
// Navigate to Job Cards
Get.toNamed('/manufacturing/job-cards');

// Navigate to Work Orders
Get.toNamed('/manufacturing/work-orders');

// Navigate to BOM
Get.toNamed('/manufacturing/bom');
```

---

## 💉 Dependency Injection

### Already Configured via Bindings!

Each route has its binding configured:

```dart
// lib/app/routes/manufacturing_routes.dart

class BomBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<BomController>(() => BomController());
  }
}

class WorkOrderBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<WorkOrderController>(() => WorkOrderController());
  }
}

class JobCardBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<JobCardController>(() => JobCardController());
  }
}
```

**How it works:**
- Controllers are created only when needed (lazy loading)
- Automatically disposed when screen is closed
- No memory leaks
- Optimal performance

### Manual Controller Access (if needed)

```dart
// Get controller instance
final jobCardController = Get.find<JobCardController>();

// Call methods
jobCardController.fetchJobCards();
jobCardController.startJobCard('JC-001');
```

---

## 🧭 Navigation Menu Integration

### Add Manufacturing Menu to Your App

**Example: Bottom Navigation Bar**

```dart
BottomNavigationBar(
  items: [
    BottomNavigationBarItem(
      icon: Icon(Icons.home),
      label: 'Home',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.factory),  // Manufacturing icon
      label: 'Production',
    ),
    // ... other items
  ],
  onTap: (index) {
    if (index == 1) {
      // Navigate to manufacturing
      Get.toNamed('/manufacturing/job-cards');
    }
  },
)
```

**Example: Drawer Menu**

```dart
Drawer(
  child: ListView(
    children: [
      // ... other items
      
      ExpansionTile(
        leading: Icon(Icons.factory, size: 28),
        title: Text('Manufacturing', style: TextStyle(fontSize: 18)),
        children: [
          ListTile(
            leading: Icon(Icons.assignment),
            title: Text('Job Cards'),
            onTap: () => Get.toNamed('/manufacturing/job-cards'),
          ),
          ListTile(
            leading: Icon(Icons.work),
            title: Text('Work Orders'),
            onTap: () => Get.toNamed('/manufacturing/work-orders'),
          ),
          ListTile(
            leading: Icon(Icons.description),
            title: Text('Bill of Materials'),
            onTap: () => Get.toNamed('/manufacturing/bom'),
          ),
        ],
      ),
    ],
  ),
)
```

**Example: Dashboard Cards**

```dart
GridView.count(
  crossAxisCount: 2,
  children: [
    // ... other cards
    
    DashboardCard(
      icon: Icons.assignment,
      title: 'Job Cards',
      color: Colors.blue,
      onTap: () => Get.toNamed('/manufacturing/job-cards'),
    ),
    DashboardCard(
      icon: Icons.work,
      title: 'Work Orders',
      color: Colors.orange,
      onTap: () => Get.toNamed('/manufacturing/work-orders'),
    ),
    DashboardCard(
      icon: Icons.description,
      title: 'BOMs',
      color: Colors.green,
      onTap: () => Get.toNamed('/manufacturing/bom'),
    ),
  ],
)
```

---

## 🧪 Testing

### Permission Testing Checklist

#### Test as Manufacturing Manager
- [ ] Can view all BOMs
- [ ] Can create new BOMs
- [ ] Can edit BOMs
- [ ] Can delete BOMs
- [ ] Can view all Work Orders
- [ ] Can create Work Orders
- [ ] Can start/stop production
- [ ] Can view all Job Cards
- [ ] Can modify any Job Card

#### Test as Supervisor
- [ ] Can view BOMs (read-only)
- [ ] Can view Work Orders
- [ ] Can start/stop Work Orders
- [ ] Can view Job Cards
- [ ] Can start/pause/complete Job Cards
- [ ] Cannot delete any documents

#### Test as Labourer
- [ ] Cannot see BOM screen
- [ ] Can view Work Orders (read-only)
- [ ] Can view Job Cards assigned to them
- [ ] Can start/pause their Job Cards
- [ ] Can add completed quantity
- [ ] Can complete their Job Cards
- [ ] Cannot modify other labourers' Job Cards

### Route Testing

```dart
// Test navigation
void testManufacturingRoutes() {
  // Test Job Cards route
  Get.toNamed('/manufacturing/job-cards');
  expect(Get.currentRoute, '/manufacturing/job-cards');
  
  // Test Work Orders route
  Get.toNamed('/manufacturing/work-orders');
  expect(Get.currentRoute, '/manufacturing/work-orders');
  
  // Test BOM route
  Get.toNamed('/manufacturing/bom');
  expect(Get.currentRoute, '/manufacturing/bom');
}
```

### Controller Testing

```dart
// Test dependency injection
void testControllers() {
  // Navigate to screen (triggers binding)
  Get.toNamed('/manufacturing/job-cards');
  
  // Controller should be available
  final controller = Get.find<JobCardController>();
  expect(controller, isNotNull);
  
  // Test controller methods
  controller.fetchJobCards();
  expect(controller.isLoading.value, true);
}
```

---

## 🔧 Troubleshooting

### Issue 1: "Permission Denied" Error

**Symptoms:**
- User sees "You don't have permission" message
- Screens show empty or error

**Solutions:**
1. Check ERPNext role assignment
   ```
   Setup > Users > [User] > Check roles assigned
   ```

2. Verify DocType permissions
   ```
   Setup > Permissions > [DocType] > Check role permissions
   ```

3. Reload permissions in ERPNext
   ```python
   # Run in console
   frappe.clear_cache()
   frappe.db.commit()
   ```

---

### Issue 2: Routes Not Working

**Symptoms:**
- Navigation does nothing
- "Route not found" error

**Solutions:**
1. Check routes are imported in main app
   ```dart
   import 'package:multimax/app/routes/manufacturing_routes.dart';
   ```

2. Verify GetX is initialized
   ```dart
   GetMaterialApp(
     getPages: ManufacturingRoutes.routes,
     // ...
   )
   ```

3. Check route names match exactly
   ```dart
   Get.toNamed('/manufacturing/job-cards');  // Correct
   Get.toNamed('/manufacturing/jobcards');   // Wrong!
   ```

---

### Issue 3: Controller Not Found

**Symptoms:**
- "Controller not found" error
- Screen shows blank

**Solutions:**
1. Check binding is added to route
   ```dart
   GetPage(
     name: jobCards,
     page: () => const JobCardScreen(),
     binding: JobCardBinding(),  // Must have this!
   )
   ```

2. Verify controller import
   ```dart
   import 'package:multimax/app/modules/manufacturing/job_card/job_card_controller.dart';
   ```

3. Use GetView instead of StatelessWidget
   ```dart
   class JobCardScreen extends GetView<JobCardController> {
     // Auto-finds controller
   }
   ```

---

### Issue 4: Data Not Loading

**Symptoms:**
- Screens show "No data"
- Loading spinner never stops

**Solutions:**
1. Check API connectivity
   ```dart
   // Test in controller
   print('API URL: ${_provider.baseUrl}');
   ```

2. Verify ERPNext API is enabled
   ```
   Setup > System Settings > Enable API Access = Yes
   ```

3. Check authentication token
   ```dart
   // In ErpnextProvider
   print('Auth Token: ${headers['Authorization']}');
   ```

4. Test DocType access in ERPNext
   ```
   Try accessing: https://your-site.com/api/resource/Job%20Card
   ```

---

### Issue 5: Middleware Blocking Access

**Symptoms:**
- Redirected to login/home
- "Insufficient permissions" message

**Solutions:**
1. Check PermissionMiddleware implementation
   ```dart
   // In lib/app/middleware/permission_middleware.dart
   // Verify logic matches your auth system
   ```

2. Temporarily disable middleware for testing
   ```dart
   GetPage(
     name: jobCards,
     page: () => const JobCardScreen(),
     binding: JobCardBinding(),
     // middlewares: [...],  // Comment out for testing
   )
   ```

3. Add debug logging
   ```dart
   print('User roles: ${currentUser.roles}');
   print('Required roles: $requiredRoles');
   ```

---

## ✅ Integration Checklist

### ERPNext Setup
- [ ] Manufacturing module enabled
- [ ] Roles created (Manager, User, Supervisor, Labourer)
- [ ] BOM permissions configured
- [ ] Work Order permissions configured
- [ ] Job Card permissions configured
- [ ] Users assigned to roles
- [ ] Sample data created (BOM, Work Order, Job Card)

### App Integration
- [ ] Manufacturing routes imported
- [ ] Routes added to main app pages
- [ ] Navigation menu updated
- [ ] Bindings verified
- [ ] Permission middleware configured
- [ ] API provider configured

### Testing
- [ ] Routes navigate correctly
- [ ] Controllers load without errors
- [ ] Data fetches from ERPNext
- [ ] Permissions enforced correctly
- [ ] All user roles tested
- [ ] Mobile UI responsive
- [ ] Production floor tested with actual users

---

## 📱 Quick Start for End Users

### For Labourers
1. Open app on tablet/phone
2. Tap "Production" or "Job Cards"
3. Find your job card (shows your operation)
4. Tap card to open
5. Tap big green "START WORK" button
6. When done, tap "ADD QUANTITY" and enter number
7. When all done, tap "COMPLETE JOB"

### For Supervisors
1. Open "Work Orders" screen
2. See all production orders
3. Tap order to see details
4. Check materials (should be green)
5. Tap "START PRODUCTION"
6. Monitor progress
7. Tap "VIEW JOB CARDS" to see worker progress

### For Managers
1. Access all three screens (BOM, Work Orders, Job Cards)
2. Create BOMs in ERPNext first
3. Create Work Orders from BOMs
4. Work Orders auto-create Job Cards
5. Assign Job Cards to workers
6. Monitor real-time progress in app

---

## 🎯 Next Steps

1. **Complete Testing**
   - Test with real production data
   - Get feedback from labourers
   - Refine UI based on usage

2. **Add Features** (Future)
   - Barcode scanning for materials
   - Photo upload for quality issues
   - Push notifications for job assignments
   - Offline mode with sync

3. **Training**
   - Train supervisors first
   - Hands-on sessions with labourers
   - Create quick reference cards
   - Video tutorials for common tasks

4. **Monitoring**
   - Track adoption metrics
   - Monitor error rates
   - Collect user feedback
   - Iterate and improve

---

**Setup complete! Your manufacturing module is ready for production use.** 🎉