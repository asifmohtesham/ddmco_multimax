# enrol.py places the reviewed DN-submit handler and approved_enrolment above this code.
# Run as one Python batch in ERP System Console with Commit checked, during the voucher pause.
workflow = frappe.db.get_value(
    "Workflow", "POS Upload Delivery", ["is_active", "document_type", "workflow_state_field"], as_dict=True,
)
if not workflow or not workflow.is_active or workflow.document_type != "POS Upload" or workflow.workflow_state_field != "status":
    frappe.throw("Activate the POS Upload Delivery Workflow before enrolling records.")

if frappe.db.get_value("Webhook", "POS Upload Delivery", "enabled"):
    frappe.throw("Disable the POS Upload Delivery webhook before enrolling records.")

# Check the whole approved list under locks before calling the existing DN-submit handler.
notes_to_enrol = []
for row in approved_enrolment:
    name = row["pos"]
    if not name.startswith(("ML-", "KA-")) or not frappe.db.get_value("POS Upload", name, "name", for_update=True):
        frappe.throw(f"{name}: expected an ML/KA POS Upload.")
    pos = frappe.get_doc("POS Upload", name, for_update=True)
    if pos.name != name or pos.docstatus != 0 or (pos.status or "Pending") not in ("Pending", "In Progress"):
        frappe.throw(f"{name}: POS Upload is no longer open.")
    if frappe.utils.get_datetime(pos.modified) != frappe.utils.get_datetime(row["modified"]):
        frappe.throw(f"{name}: POS revision changed. Refresh the approved list.")
    notes = frappe.db.sql(
        """select name from `tabDelivery Note`
           where po_no = %s and docstatus = 1 and is_return = 0 limit 2 for update""",
        (name,), as_dict=True,
    )
    if len(notes) != 1 or notes[0].name != row["dn"]:
        frappe.throw(f"{name}: expected the approved single submitted outbound Delivery Note.")
    note = frappe.get_doc("Delivery Note", row["dn"], for_update=True)
    if note.po_no != name or note.company != "Multimax" or note.customer != pos.customer or (note.total_qty or 0) <= 0:
        frappe.throw(f"{name}: the approved Delivery Note is ineligible.")
    if frappe.db.get_value("Delivery Note", {
        "return_against": note.name, "docstatus": 1, "is_return": 1,
    }, "name", for_update=True):
        frappe.throw(f"{name}: a submitted stock return exists.")
    notes_to_enrol.append(note)

for note in notes_to_enrol:
    handle_voucher(note, "submit", 1)
    current = frappe.db.get_value("POS Upload", note.po_no, ["status", "modified"], as_dict=True, for_update=True)
    if current.status != "To Deliver":
        frappe.throw(f"{note.po_no}: the DN-submit handler did not enter To Deliver.")
    version = frappe.db.get_value(
        "Version", {"ref_doctype": "POS Upload", "docname": note.po_no}, ["name", "data"],
        order_by="creation desc", as_dict=True, for_update=True,
    )
    data = json.loads(version.data) if version else {}
    audit = (data.get("updater_reference") or {}).get("pos_delivery") or {}
    status_change = any(change[0] == "status" and change[1] != change[2] and change[2] == "To Deliver"
                        for change in data.get("changed", []))
    if (not status_change or audit.get("dn") != note.name or not audit.get("comment_id") or not audit.get("modified")
            or frappe.utils.get_datetime(audit.get("modified")) != frappe.utils.get_datetime(current.modified)):
        frappe.throw(f"{note.po_no}: the matching delivery Version audit is missing.")
    print(f"Enrolled {note.po_no} / {note.name} at {current.modified} (Version {version.name})")

print(f"Enrolled {len(notes_to_enrol)} POS Uploads.")
