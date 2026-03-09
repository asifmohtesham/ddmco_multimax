# Manufacturing Module - ERPNext Permissions Guide

## 🔐 Overview

This guide explains how to configure ERPNext permissions for the Manufacturing module to ensure proper access control for different user roles.

---

## 👥 User Roles

### Role Hierarchy

```
Manufacturing Manager
    |
    ├─ Production Supervisor
    │      |
    │      └─ Production Worker (Labourer)
    |
    └─ BOM Manager
```

### Role Definitions

#### 1. **Manufacturing Manager** (Full Access)
- **Permissions**: All DocTypes (Read, Write, Create, Delete, Submit, Cancel)
- **Use Case**: Overall manufacturing oversight
- **Access**:
  - All BOMs
  - All Work Orders
  - All Job Cards
  - Manufacturing settings
  - Reports and analytics

#### 2. **Production Supervisor** (Management Access)
- **Permissions**: Work Orders, Job Cards (Read, Write, Submit)
- **Use Case**: Floor supervision and coordination
- **Access**:
  - View all Work Orders
  - Start/stop production
  - Assign Job Cards to workers
  - View BOM (read-only)
  - Monitor progress

#### 3. **Production Worker** (Limited Access)
- **Permissions**: Assigned Job Cards only (Read, Write)
- **Use Case**: Production floor operations
- **Access**:
  - View assigned Job Cards only
  - Start/stop timer on own Job Cards
  - Update completed quantity
  - Cannot create or delete
  - Cannot access other workers' cards

#### 4. **BOM Manager** (BOM Only)
- **Permissions**: BOM (Read, Write, Create, Delete, Submit)
- **Use Case**: Product engineering and costing
- **Access**:
  - All BOM operations
  - View Work Orders (read-only)
  - Cannot manage Job Cards

---

## ⚙️ ERPNext Permission Configuration

### Step 1: Create Custom Roles

**In ERPNext:**

1. Go to: **Setup → Permissions → Role**
2. Create these roles:
   - `Manufacturing Manager`
   - `Production Supervisor`
   - `Production Worker`
   - `BOM Manager`

---

### Step 2: Configure BOM Permissions

**DocType:** `BOM`

| Role | Level | Perm Read | Perm Write | Create | Delete | Submit | Cancel | Report |
|------|-------|-----------|------------|--------|--------|--------|--------|--------|
| **Manufacturing Manager** | 0 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **BOM Manager** | 0 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Production Supervisor** | 0 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| **Production Worker** | 0 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

**Commands:**
```python
# In ERPNext Console
frappe.permissions.add_permission('BOM', 'Manufacturing Manager', 0)
frappe.permissions.add_permission('BOM', 'BOM Manager', 0)
frappe.permissions.add_permission('BOM', 'Production Supervisor', 0, read_only=1)
```

---

### Step 3: Configure Work Order Permissions

**DocType:** `Work Order`

| Role | Level | Perm Read | Perm Write | Create | Delete | Submit | Cancel | Report |
|------|-------|-----------|------------|--------|--------|--------|--------|--------|
| **Manufacturing Manager** | 0 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Production Supervisor** | 0 | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ |
| **Production Worker** | 0 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **BOM Manager** | 0 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

**User Permission Rules:**
```python
# Production Workers can only see their assigned Work Orders
# Add in User Permission:
User: [worker_email]
Allow: Work Order
For Value: [specific_work_order]
```

---

### Step 4: Configure Job Card Permissions

**DocType:** `Job Card`

| Role | Level | Perm Read | Perm Write | Create | Delete | Submit | Cancel | Report |
|------|-------|-----------|------------|--------|--------|--------|--------|--------|
| **Manufacturing Manager** | 0 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Production Supervisor** | 0 | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ |
| **Production Worker** | 0 | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ |
| **BOM Manager** | 0 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

**User Permission Rules (Critical for Workers):**
```python
# Workers can ONLY access Job Cards assigned to them
# Method 1: By Employee
User: worker@company.com
Allow: Job Card
Applicable For: Employee
For Value: EMP-00123

# Method 2: By Workstation
User: worker@company.com
Allow: Job Card
Applicable For: Workstation
For Value: WS-WELDING-01
```

**Restrict by Employee:**
```python
# In Job Card DocType, add permission query:
frappe.db.set_value('DocType', 'Job Card', 'permissions', [
    {
        'role': 'Production Worker',
        'if_owner': 0,
        'match': 'employee'
    }
])
```

---

## 🔑 API Key Configuration

### Create API Users

**For Mobile App Access:**

1. **Create API User**
   - Go to: **User → Add User**
   - Email: `manufacturing_app@company.com`
   - Full Name: `Manufacturing Mobile App`
   - Roles: Assign appropriate role

2. **Generate API Keys**
   ```bash
   # In ERPNext Console
   api_key = frappe.generate_hash(length=20)
   api_secret = frappe.generate_hash(length=40)
   
   user = frappe.get_doc('User', 'manufacturing_app@company.com')
   user.api_key = api_key
   user.api_secret = api_secret
   user.save()
   
   print(f"API Key: {api_key}")
   print(f"API Secret: {api_secret}")
   ```

3. **Configure in App**
   ```dart
   // In app configuration
   const API_KEY = 'your_api_key_here';
   const API_SECRET = 'your_api_secret_here';
   ```

---

## 🛡️ Security Best Practices

### 1. Principle of Least Privilege

```python
# Grant minimum permissions needed
# ✅ Good: Worker can only update their job cards
Permissions: Read, Write (own Job Cards only)

# ❌ Bad: Worker has access to all job cards
Permissions: Read, Write (all Job Cards)
```

### 2. User Permission Filters

**For Production Workers:**
```python
# Restrict by employee
frappe.permissions.add(
    doctype='Job Card',
    role='Production Worker',
    user_permission_doctypes=['Employee'],
    user_permission_values=[current_user.employee]
)
```

### 3. Field-Level Permissions

**Hide sensitive fields from workers:**
```json
// Job Card customization
{
  "field": "operating_cost",
  "hidden": 1,
  "roles": ["Production Worker"]
}
```

### 4. Time-Based Restrictions

```python
# Prevent future-dating
def validate(self):
    if self.actual_start_date > now():
        frappe.throw("Cannot start job in the future")
```

---

## 📱 App-Specific Permissions

### Controller-Level Access Control

```dart
// In JobCardController
Future<void> fetchJobCards() async {
  final userRole = Get.find<AuthController>().userRole;
  
  final filters = <String, dynamic>{};
  
  // Apply role-based filtering
  if (userRole == 'Production Worker') {
    // Only fetch assigned job cards
    filters['employee'] = currentUserEmployee;
  } else if (userRole == 'Production Supervisor') {
    // Fetch all job cards in assigned area
    filters['workstation'] = ['in', assignedWorkstations];
  }
  // Manufacturing Manager sees all (no filter)
  
  final response = await _provider.getListWithFilters(
    doctype: 'Job Card',
    filters: filters,
  );
}
```

### UI-Level Permission Checks

```dart
// Hide buttons based on role
if (userRole == 'Production Worker')
  ElevatedButton(
    onPressed: canStart ? startJob : null,
    child: Text('START WORK'),
  ),

// Supervisors see additional options
if (userRole == 'Production Supervisor' || userRole == 'Manufacturing Manager')
  ElevatedButton(
    onPressed: () => assignToWorker(),
    child: Text('ASSIGN WORKER'),
  ),
```

---

## 🧪 Testing Permissions

### Test Cases

#### Test 1: Production Worker Permissions
```bash
# Login as worker
User: worker1@company.com

✅ Should see: Own job cards only
❌ Should NOT see: Other workers' job cards
✅ Can do: Start/stop timer, update quantity
❌ Cannot do: Delete, assign to others, view cost
```

#### Test 2: Supervisor Permissions
```bash
# Login as supervisor
User: supervisor@company.com

✅ Should see: All job cards, all work orders
❌ Should NOT see: BOM costs (if restricted)
✅ Can do: Start work orders, assign job cards
❌ Cannot do: Delete BOMs, modify costs
```

#### Test 3: API Key Authentication
```bash
# Test API call with worker credentials
curl -X GET "https://yoursite.com/api/resource/Job Card" \
  -H "Authorization: token api_key:api_secret"

# Should return only assigned job cards
```

---

## 🚨 Troubleshooting

### Issue 1: "No Permission" Error

**Symptom:** App shows "You don't have permission to access Job Card"

**Solutions:**
1. Check user has correct role assigned
2. Verify Role Permission exists for DocType
3. Check User Permission filters
4. Ensure document is not restricted by owner

```python
# Debug in ERPNext Console
frappe.permissions.get_valid_perms(
    doctype='Job Card',
    user='worker@company.com'
)
```

### Issue 2: Worker Sees All Job Cards

**Symptom:** Worker can see other workers' job cards

**Solution:**
```python
# Add User Permission
frappe.share.add(
    doctype='Job Card',
    name=job_card_name,
    user=worker_email,
    read=1,
    write=1,
    submit=1
)

# Or use match condition
frappe.permissions.add_user_permission(
    doctype='Employee',
    name=employee_id,
    user=worker_email,
    applicable_for='Job Card'
)
```

### Issue 3: API Authentication Fails

**Symptom:** 401 Unauthorized error

**Check:**
1. API key format: `api_key:api_secret`
2. User has API access enabled
3. API secret not expired
4. Correct base URL

```python
# Regenerate API keys
user = frappe.get_doc('User', 'app_user@company.com')
user.api_key = frappe.generate_hash(length=15)
user.api_secret = frappe.generate_hash(length=15)
user.save()
```

---

## 📋 Permission Setup Checklist

### Initial Setup
- [ ] Create custom roles (Manufacturing Manager, Supervisor, Worker, BOM Manager)
- [ ] Configure BOM permissions
- [ ] Configure Work Order permissions
- [ ] Configure Job Card permissions
- [ ] Set up User Permissions for workers
- [ ] Create API users
- [ ] Generate API keys
- [ ] Configure app with API credentials

### Security Audit
- [ ] Verify workers can only see assigned job cards
- [ ] Test supervisor can manage all operations
- [ ] Confirm cost data hidden from workers (if required)
- [ ] Check API authentication works
- [ ] Test permission boundaries (try unauthorized actions)
- [ ] Review access logs

### Production Deployment
- [ ] Change default passwords
- [ ] Rotate API keys
- [ ] Enable SSL/HTTPS
- [ ] Set up IP whitelisting (if needed)
- [ ] Configure session timeout
- [ ] Enable audit logs
- [ ] Document emergency access procedures

---

## 📞 Support

For permission issues:
1. Check ERPNext error log: **Home → Error Log**
2. Review permission query: **DocType → [DocType Name] → Permissions**
3. Test in ERPNext UI first before troubleshooting app
4. Use ERPNext console for debugging

---

**Security Note:** Always test permissions in a staging environment before deploying to production. Never share API keys in code repositories.