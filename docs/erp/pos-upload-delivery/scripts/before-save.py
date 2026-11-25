# Only the synchronous workflow task can grant a protected save.
def data_values(record, ignored):
    return {key: value for key, value in record.get_valid_dict().items() if key not in ignored}


def business_fields_changed(document, previous, values=data_values):
    metadata = ("modified", "modified_by", "creation", "owner", "status", "custom_return_reason")
    if values(document, metadata) != values(previous, metadata):
        return True
    for field in document.meta.get_table_fields():
        current_rows = [values(row, metadata) for row in document.get(field.fieldname) or []]
        previous_rows = [values(row, metadata) for row in previous.get(field.fieldname) or []]
        if current_rows != previous_rows:
            return True
    return False


def can_edit_warehouse_fields(document, user):
    if user == "Administrator":
        return True
    roles = frappe.get_all("Has Role", filters={"parenttype": "User", "parent": user}, pluck="role")
    for permission in document.meta.permissions:
        if (
            permission.permlevel == 0 and permission.write and permission.role in roles
            and permission.role not in ("Delivery Dispatcher", "Stock Manager")
            and (not permission.if_owner or document.owner == user)
        ):
            return True
    return False


before = doc.get_doc_before_save()
approval = doc.flags.get("pos_delivery_action")
use_actions = "Delivery status and Return Reason are managed by the workflow. Reload the POS Upload and use Actions."
if not before:
    if doc.status not in (None, "", "Pending") or doc.custom_return_reason:
        frappe.throw(use_actions)
    doc.status = "Pending"
elif approval:
    if (
        approval.get("revision") != str(before.modified)
        or approval.get("status") != doc.status
        or approval.get("reason") != (doc.custom_return_reason or "")
        or business_fields_changed(doc, before)
    ):
        frappe.throw("This POS Upload changed. Reload it and use Actions again.")
    doc.flags.updater_reference["pos_delivery"]["modified"] = str(doc.modified)
else:
    old_status = before.status or "Pending"
    if doc.status != before.status and not (old_status == "Pending" and doc.status == "Pending"):
        frappe.throw(use_actions)
    if (doc.custom_return_reason or "") != (before.custom_return_reason or ""):
        frappe.throw(use_actions)
    if old_status not in ("Pending", "In Progress") or not can_edit_warehouse_fields(doc, frappe.session.user):
        frappe.throw("This POS Upload cannot be edited here. Use Actions for delivery changes.")
