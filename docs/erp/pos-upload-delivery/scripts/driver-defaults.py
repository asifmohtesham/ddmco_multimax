# Authenticated API Server Script: pos_upload_delivery_drivers
user = frappe.session.user
if user != "Administrator" and not frappe.db.exists(
    "Has Role",
    {
        "parent": user,
        "parenttype": "User",
        "parentfield": "roles",
        "role": ["in", ["Delivery Dispatcher", "Stock Manager"]],
    },
):
    frappe.throw("Delivery Dispatcher or Stock Manager is required.", frappe.PermissionError)

name = frappe.form_dict.get("name")
action = frappe.form_dict.get("action")
if not isinstance(name, str) or not name or action not in (
    "Out for Delivery",
    "Delivery Return",
    "Delivered",
):
    frappe.throw("Provide a POS Upload name and a delivery action.")

pos = frappe.get_doc("POS Upload", name)
pos.check_permission("read")

drivers = frappe.get_all(
    "Driver",
    filters={"status": "Active"},
    fields=["name", "full_name", "user", "employee"],
    order_by="full_name asc, name asc",
)
choices = []
active_names = set()
mapped = []
for driver in drivers:
    choices.append({"name": driver.name, "full_name": driver.full_name})
    active_names.add(driver.name)
    employee_user = None
    if driver.employee:
        employee_user = frappe.db.get_value(
            "Employee", {"name": driver.employee, "status": "Active"}, "user_id"
        )
    if driver.user and employee_user and driver.user != employee_user:
        continue
    if (driver.user or employee_user) == user:
        mapped.append(driver.name)

default_driver = mapped[0] if len(mapped) == 1 else None
if not default_driver and pos.status == "Out for Delivery" and action in (
    "Delivery Return",
    "Delivered",
):
    offset = 0
    page_size = 30
    found_dispatch = False
    while not found_dispatch:
        versions = frappe.get_all(
            "Version",
            filters={"ref_doctype": "POS Upload", "docname": pos.name},
            fields=["data"],
            order_by="creation desc, name desc",
            limit_start=offset,
            limit_page_length=page_size,
        )
        for version in versions:
            data = json.loads(version.data or "{}")
            reference = data.get("updater_reference")
            audit = reference.get("pos_delivery") if isinstance(reference, dict) else None
            if not isinstance(audit, dict) or audit.get("action") != "Out for Delivery":
                continue
            if ["status", "To Deliver", "Out for Delivery"] in (data.get("changed") or []):
                if audit.get("driver") in active_names:
                    default_driver = audit.get("driver")
                found_dispatch = True
                break
        if len(versions) < page_size:
            break
        offset += page_size

frappe.response["message"] = {"drivers": choices, "default_driver": default_driver}
