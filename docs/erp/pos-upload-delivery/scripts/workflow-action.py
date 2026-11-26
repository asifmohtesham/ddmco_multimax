# Synchronous task of the native POS Upload Delivery workflow.
# The core reloads the document, so only the original RPC argument carries picker input.
def current_dispatch_dn(pos_name):
    start = 0
    while True:
        versions = frappe.get_all(
            "Version", filters={"ref_doctype": "POS Upload", "docname": pos_name},
            fields=["data"], order_by="creation desc, name desc", start=start, page_length=20,
        )
        for row in versions:
            data = json.loads(row.data)
            for change in data.get("changed", []):
                if change[0] == "status" and change[2] == "Out for Delivery":
                    detail = (data.get("updater_reference") or {}).get("pos_delivery") or {}
                    return detail.get("dn") if detail.get("action") == "Out for Delivery" else None
        if len(versions) < 20:
            return None
        start = start + len(versions)


def eligible_dn(pos_name, customer, required):
    notes = frappe.db.sql(
        """select name, customer, company, total_qty from `tabDelivery Note`
           where po_no = %s and docstatus = 1 and is_return = 0 limit 2 for update""",
        (pos_name,), as_dict=True,
    )
    if len(notes) == 0 and required:
        frappe.throw("No submitted outbound Delivery Note found for this POS Upload.")
    if len(notes) > 1 and required:
        frappe.throw("Multiple submitted outbound Delivery Notes are linked. Ask Stock Manager to reconcile them.")
    if len(notes) != 1:
        return None
    note = notes[0]
    if required and (note.company != "Multimax" or note.customer != customer or not (note.total_qty or 0) > 0):
        frappe.throw("The submitted Delivery Note must be for Multimax, match the POS customer and have positive quantity.")
    if required and frappe.db.get_value(
        "Delivery Note", {"return_against": note.name, "docstatus": 1, "is_return": 1},
        "name", for_update=True,
    ):
        frappe.throw("The submitted Delivery Note has a submitted stock return. Ask Stock Manager to reconcile it.")
    return note.name


request_doc = frappe.form_dict.get("doc")
if isinstance(request_doc, str):
    request_doc = json.loads(request_doc)
requested_action = frappe.form_dict.get("action")
edges = {
    "Out for Delivery": ("To Deliver", "Out for Delivery"),
    "Delivery Return": ("Out for Delivery", "To Deliver"),
    "Delivered": ("Out for Delivery", "Delivered"),
    "Revert to Pending": ("In Progress", "Pending"),
    "Complete": ("Delivered", "Completed"),
}
edge = edges.get(requested_action)
locked = frappe.db.get_value("POS Upload", doc.name, ["status", "modified", "customer"], as_dict=True, for_update=True)
if (
    not isinstance(request_doc, dict) or request_doc.get("doctype") != "POS Upload"
    or request_doc.get("name") != doc.name or not locked or not edge
    or request_doc.get("modified") != str(locked.modified) or str(doc.modified) != str(locked.modified)
    or (locked.status, doc.status) != edge
):
    frappe.throw("This POS Upload changed. Reload it and use Actions again.")

user = frappe.session.user
recorded_by_name = frappe.db.get_value("User", user, "full_name") or user
if requested_action == "Revert to Pending":
    # Stock Manager reopens preparation so the POS can be edited (e.g. re-imported) again.
    # No driver, reason or Delivery Note; the Version and comment keep the audit.
    driver = None
    driver_name = None
    reason = None
    dn = None
    doc.custom_return_reason = ""
    text = f"POS delivery · Revert to Pending · recorded by {frappe.utils.escape_html(recorded_by_name)}"
elif requested_action == "Complete":
    # Stock Manager closes a delivered DN-route POS, so every finished POS Upload ends in Completed
    # (as Stock Entry-route ones already do). The delivered Delivery Note must still stand:
    # a replacement submitted after delivery was never dispatched, so it can't close the POS.
    driver = None
    driver_name = None
    reason = None
    dn = eligible_dn(doc.name, locked.customer, True)
    if dn != current_dispatch_dn(doc.name):
        frappe.throw("The Delivery Note has changed since it was delivered. Reconcile it before completing the POS Upload.")
    text = (
        f"POS delivery · Complete · recorded by {frappe.utils.escape_html(recorded_by_name)}"
        f" · Delivery Note: {frappe.utils.escape_html(dn)}"
    )
else:
    driver_id = request_doc.get("pos_delivery_driver")
    if not isinstance(driver_id, str) or not driver_id:
        frappe.throw("Select an active Driver.")
    driver = frappe.db.get_value("Driver", {"name": driver_id, "status": "Active"}, ["name", "full_name"], as_dict=True)
    if not driver:
        frappe.throw("Select an active Driver.")

    reason = request_doc.get("pos_delivery_reason")
    if requested_action == "Delivery Return":
        if reason not in ("Late", "Rejected", "Other"):
            frappe.throw("Select a Return Reason (Late, Rejected or Other).")
        doc.custom_return_reason = reason
    else:
        if reason:
            frappe.throw("Return Reason is only accepted for Delivery Return.")
        if requested_action == "Out for Delivery":
            doc.custom_return_reason = ""

    dn = eligible_dn(doc.name, locked.customer, requested_action != "Delivery Return")
    if requested_action == "Delivered" and dn != current_dispatch_dn(doc.name):
        frappe.throw("The Delivery Note has changed since dispatch. Record a Delivery Return and dispatch the replacement before marking Delivered.")

    driver_name = driver.full_name or driver.name
    text = (
        f"POS delivery · {requested_action} · Driver: {frappe.utils.escape_html(driver_name)}"
        f" · recorded by {frappe.utils.escape_html(recorded_by_name)}"
    )
    if reason:
        text = text + f" · Reason: {reason}"
    if dn:
        text = text + f" · Delivery Note: {frappe.utils.escape_html(dn)}"
comment = doc.add_comment("Workflow", text)
doc.flags.pos_delivery_action = {
    "revision": str(locked.modified), "status": doc.status, "reason": doc.custom_return_reason or "",
}
doc.flags.updater_reference = {
    "doctype": "POS Upload", "docname": doc.name, "label": requested_action,
    "pos_delivery": {
        "action": requested_action, "driver": driver.name if driver else None, "driver_name": driver_name,
        "recorded_by": user, "recorded_by_name": recorded_by_name,
        "reason": reason or None, "dn": dn, "comment_id": comment.name,
    },
}
