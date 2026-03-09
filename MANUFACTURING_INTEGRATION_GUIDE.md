# Manufacturing Module Integration Guide

## 📋 Overview

This guide walks through integrating the Manufacturing module into your main application.

---

## 🔧 Step 1: Add Routes to Main App

### Update `lib/app/routes/app_pages.dart`

```dart
import 'package:multimax/app/routes/manufacturing_routes.dart';

class AppPages {
  static const INITIAL = Routes.HOME;

  static final routes = [
    // ... existing routes ...
    
    // Manufacturing Module Routes
    ...ManufacturingRoutes.routes,
    
    // Manufacturing Home
    GetPage(
      name: '/manufacturing',
      page: () => const ManufacturingHome(),
      middlewares: [
        PermissionMiddleware(
          requiredPermissions: ['Manufacturing', 'read'],
          roles: ['Manufacturing Manager', 'Manufacturing User', 'Supervisor', 'Labourer'],
        ),
      ],
    ),
  ];
}
```

---

## 🗺️ Step 2: Add Navigation Menu Item

### Option A: Bottom Navigation Bar

```dart
// In your main scaffold/home screen
BottomNavigationBar(
  items: const [
    BottomNavigationBarItem(
      icon: Icon(Icons.home),
      label: 'Home',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.factory),
      label: 'Manufacturing',
    ),
    // ... other items ...
  ],
  onTap: (index) {
    if (index == 1) {
      Get.toNamed('/manufacturing');
    }
  },
)
```

### Option B: Drawer Menu

```dart
Drawer(
  child: ListView(
    children: [
      // ... other items ...
      
      ListTile(
        leading: const Icon(Icons.factory),
        title: const Text('Manufacturing'),
        onTap: () {
          Get.back(); // Close drawer
          Get.toNamed('/manufacturing');
        },
      ),
    ],
  ),
)
```

### Option C: Dashboard Card

```dart
// On your main dashboard
GridView(
  children: [
    DashboardCard(
      icon: Icons.factory,
      title: 'Manufacturing',
      onTap: () => Get.toNamed('/manufacturing'),
    ),
    // ... other cards ...
  ],
)
```

---

## 🔐 Step 3: Configure ERPNext Permissions

### Create Roles in ERPNext

1. **Login to ERPNext as Administrator**

2. **Create Roles** (Setup > Role)
   - Manufacturing Manager
   - Manufacturing User
   - Supervisor
   - Labourer

3. **Set Role Permissions** for each DocType:

#### BOM Permissions
```
Role                    | Read | Write | Create | Delete | Submit
------------------------|------|-------|--------|--------|--------
Manufacturing Manager   |  ✓   |   ✓   |   ✓    |   ✓    |   ✓
Manufacturing User      |  ✓   |   ✓   |   ✓    |   ✗    |   ✓
Supervisor              |  ✓   |   ✗   |   ✗    |   ✗    |   ✗
Labourer                |  ✗   |   ✗   |   ✗    |   ✗    |   ✗
```

#### Work Order Permissions
```
Role                    | Read | Write | Create | Delete | Submit
------------------------|------|-------|--------|--------|--------
Manufacturing Manager   |  ✓   |   ✓   |   ✓    |   ✓    |   ✓
Manufacturing User      |  ✓   |   ✓   |   ✓    |   ✗    |   ✓
Supervisor              |  ✓   |   ✓   |   ✗    |   ✗    |   ✓
Labourer                |  ✓   |   ✗   |   ✗    |   ✗    |   ✗
```

#### Job Card Permissions
```
Role                    | Read | Write | Create | Delete | Submit
------------------------|------|-------|--------|--------|--------
Manufacturing Manager   |  ✓   |   ✓   |   ✓    |   ✓    |   ✓
Manufacturing User      |  ✓   |   ✓   |   ✓    |   ✗    |   ✓
Supervisor              |  ✓   |   ✓   |   ✓    |   ✗    |   ✓
Labourer                |  ✓   |   ✓   |   ✗    |   ✗    |   ✓
```

### Apply Permissions

1. Go to **Setup > Permissions > Role Permissions Manager**
2. Select DocType (BOM, Work Order, Job Card)
3. Set permissions as per tables above
4. Click **Update**

---

## 👥 Step 4: Setup Users

### Create Employee Records

1. **HR > Employee > New**
2. Fill in employee details
3. Create user account
4. Assign roles

### Assign Manufacturing Roles

#### For Production Labourers:
```yaml
User: john.worker@company.com
Roles:
  - Labourer
  - Employee
Permissions:
  - Can read and update Job Cards only
  - Cannot access Work Orders or BOMs
```

#### For Supervisors:
```yaml
User: jane.supervisor@company.com
Roles:
  - Supervisor
  - Manufacturing User
  - Employee
Permissions:
  - Can read all manufacturing docs
  - Can create and update Work Orders
  - Can manage Job Cards
```

#### For Manufacturing Managers:
```yaml
User: manager@company.com
Roles:
  - Manufacturing Manager
  - Manufacturing User
  - Employee
Permissions:
  - Full access to all manufacturing features
  - Can create/edit/delete BOMs
  - Can manage all Work Orders and Job Cards
```

---

## 🏭 Step 5: Configure Manufacturing Master Data

### Create Workstations

1. **Manufacturing > Workstation > New**
2. Create workstations:
   ```
   - Welding Station 01
   - Assembly Line A
   - Quality Check Station
   - Packaging Unit
   ```

### Create Operations

1. **Manufacturing > Operation > New**
2. Define operations:
   ```
   - Cutting
   - Welding
   - Assembly
   - Quality Inspection
   - Packaging
   ```

### Create BOMs

1. **Manufacturing > BOM > New**
2. For each finished good:
   - Add item to produce
   - Add raw materials (items table)
   - Add operations (operations table)
   - Set quantities and costs
   - Save and Submit

---

## 🧪 Step 6: Testing

### Test Flow for Labourer

1. **Login as Labourer**
   ```
   Email: labourer@company.com
   Password: [set in ERPNext]
   ```

2. **Navigate to Manufacturing**
   - Should see Manufacturing home
   - Only "Job Cards" should be enabled
   - Work Orders and BOM should be locked

3. **Open Job Cards**
   - Should see list of assigned job cards
   - Tap a job card
   - Tap "START WORK"
   - Timer should start
   - Add completed quantity
   - Complete job when done

### Test Flow for Supervisor

1. **Login as Supervisor**
   ```
   Email: supervisor@company.com
   Password: [set in ERPNext]
   ```

2. **Create Work Order in ERPNext**
   - Manufacturing > Work Order > New
   - Select item to produce
   - Set quantity
   - Select BOM
   - Submit

3. **View in App**
   - Open Manufacturing > Work Orders
   - Should see new work order
   - Tap "START PRODUCTION"
   - Check status changes to "In Process"
   - Job cards should auto-generate

4. **Monitor Job Cards**
   - Open Job Cards screen
   - See all jobs for the work order
   - Monitor progress
   - Check completion status

### Test Flow for Manager

1. **Login as Manager**
   ```
   Email: manager@company.com
   Password: [set in ERPNext]
   ```

2. **View BOMs**
   - Open Manufacturing > BOM
   - Should see all BOMs
   - Tap a BOM to view details
   - Check materials and operations

3. **Full Access Verification**
   - Can access all three modules
   - Can see all data
   - Can perform all actions

---

## 🔍 Step 7: Troubleshooting

### Problem: "Permission Denied" Error

**Solution:**
1. Check ERPNext role assignments
2. Verify DocType permissions
3. Clear app cache and re-login
4. Check middleware configuration

### Problem: Routes Not Working

**Solution:**
1. Verify routes added to `app_pages.dart`
2. Check GetX binding registration
3. Ensure `ManufacturingRoutes.routes` is imported
4. Hot restart the app

### Problem: Controllers Not Found

**Solution:**
1. Check binding classes are created
2. Verify lazy loading with `Get.lazyPut`
3. Ensure ErpnextProvider is registered globally
4. Check import statements

### Problem: No Data Showing

**Solution:**
1. Verify ERPNext API connectivity
2. Check user has data in ERPNext
3. Ensure Work Orders are submitted (not draft)
4. Check Job Cards are created for Work Orders
5. Verify warehouse and workstation assignments

### Problem: Timer Not Starting

**Solution:**
1. Check job card status is "Open"
2. Verify materials are transferred
3. Check network connectivity
4. Ensure ERPNext time log API is working
5. Check console for API errors

---

## 📱 Step 8: Production Deployment

### Pre-Deployment Checklist

- [ ] All routes configured
- [ ] Permissions tested
- [ ] ERPNext roles created
- [ ] Users assigned roles
- [ ] Workstations configured
- [ ] Operations defined
- [ ] BOMs created
- [ ] Test Work Orders completed
- [ ] Job Card workflow tested
- [ ] Error handling verified
- [ ] Loading states working
- [ ] Offline mode tested

### Post-Deployment

1. **Monitor Usage**
   - Track API calls
   - Monitor error rates
   - Check user feedback

2. **Train Users**
   - Use MANUFACTURING_MVP_README.md
   - Conduct hands-on training
   - Create video tutorials

3. **Gather Feedback**
   - Survey labourers
   - Interview supervisors
   - Track completion times
   - Measure error reduction

---

## 🎯 Success Criteria

### For Labourers
- ✅ Can start job within 10 seconds
- ✅ No confusion about button functions
- ✅ Timer clearly visible
- ✅ Can add quantity without supervisor help
- ✅ Completion process takes < 30 seconds

### For Supervisors
- ✅ Can view all active work orders
- ✅ Material status immediately clear
- ✅ Can start production in 3 taps
- ✅ Job card monitoring real-time
- ✅ Progress tracking accurate

### For Managers
- ✅ Complete visibility of production floor
- ✅ BOM costs accurate
- ✅ Can track efficiency metrics
- ✅ Reports available (future)
- ✅ Data syncs with ERPNext

---

## 🚀 Next Steps (Future Enhancements)

### Phase 2 Features

1. **Material Request Integration**
   - Auto-request materials when low
   - Track material consumption
   - Warehouse transfers

2. **Quality Inspection**
   - Add quality checkpoints
   - Reject/accept workflow
   - Defect tracking

3. **Reports & Analytics**
   - Production efficiency
   - Downtime tracking
   - Cost variance analysis
   - Worker productivity

4. **Offline Mode**
   - Local data caching
   - Queue operations
   - Sync when online

5. **Notifications**
   - Job assignment alerts
   - Completion notifications
   - Material shortage warnings

---

## 📞 Support

### For Integration Issues
- Check this guide first
- Review MANUFACTURING_MVP_README.md
- Check ERPNext documentation
- Contact IT support

### For User Issues
- Refer to user workflows in README
- Check troubleshooting section
- Contact supervisor
- Escalate to manager if needed

---

**Integration Complete! 🎉**

*Your manufacturing module is now ready for production floor use.*