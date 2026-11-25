# This body is appended to each event-specific Server Script.
def handle_voucher(voucher, event, expected_docstatus):
    def review(target, voucher, event, message):
        name = frappe.utils.escape_html(voucher.name)
        prefix = f"POS delivery review · {event} · {name} · "
        if not frappe.db.exists("Comment", {
            "reference_doctype": target.doctype, "reference_name": target.name,
            "comment_type": "Workflow", "content": ["like", f"{prefix}%"],
        }):
            target.add_comment("Workflow", prefix + message)
            target.notify_update()


    def move(pos, voucher, new_status, action, dn=None):
        if pos.status == new_status:
            return
        pos.load_doc_before_save()
        user = frappe.session.user
        actor = frappe.db.get_value("User", user, "full_name") or user
        modified = frappe.utils.now()
        source = frappe.utils.escape_html(voucher.name)
        text = f"POS delivery · {action} · recorded by {frappe.utils.escape_html(actor)} · {voucher.doctype}: {source}"
        comment = pos.add_comment("Workflow", text)
        pos.status = new_status
        pos.modified = modified
        pos.modified_by = user
        pos.flags.updater_reference = {
            "doctype": voucher.doctype, "docname": voucher.name, "label": action,
            "pos_delivery": {
                "action": action, "driver": None, "driver_name": None, "recorded_by": user,
                "recorded_by_name": actor, "reason": None, "dn": dn,
                "comment_id": comment.name, "modified": str(modified),
            },
        }
        frappe.db.set_value("POS Upload", pos.name, {"status": pos.status, "modified": modified, "modified_by": user}, update_modified=False)
        pos.save_version()
        pos.notify_update()


    def submitted_outbound(pos_name):
        return frappe.db.sql(
            """select name, customer, company, total_qty from `tabDelivery Note`
               where po_no = %s and docstatus = 1 and is_return = 0 limit 2 for update""",
            (pos_name,), as_dict=True,
        )


    def is_eligible_dn(note, pos):
        return note.company == "Multimax" and note.customer == pos.customer and (note.total_qty or 0) > 0


    def has_stock_return(note_name):
        return frappe.db.get_value(
            "Delivery Note", {"return_against": note_name, "docstatus": 1, "is_return": 1}, "name", for_update=True,
        )


    def handle_dn(voucher, event):
        original = None
        if voucher.is_return:
            if event == "save" or voucher.company != "Multimax" or not voucher.return_against:
                return
            original = frappe.db.get_value(
                "Delivery Note", voucher.return_against, ["company", "is_return", "po_no"], as_dict=True,
            )
            if not original or original.is_return or original.company != "Multimax":
                return
        reference = (original.po_no if original else voucher.po_no) or ""
        if not reference.startswith(("ML-", "KA-")):
            return
        if not frappe.db.get_value("POS Upload", reference, "name", for_update=True):
            review(voucher, voucher, event, "No POS Upload matches the voucher reference.")
            return
        pos = frappe.get_doc("POS Upload", reference, for_update=True)
        current = pos.status or "Pending"
        managed = current in ("To Deliver", "Out for Delivery", "Delivered")

        if original:
            if managed:
                message = (
                    "A stock return was submitted against an outbound Delivery Note. Review the recorded delivery."
                    if event == "submit" else "A stock return was cancelled. Check current Delivery Note eligibility."
                )
                review(pos, voucher, event, message)
            return

        if event == "save":
            if not is_eligible_dn(voucher, pos):
                review(pos, voucher, event, "The draft needs Multimax, the POS customer and positive quantity.")
            elif current == "Pending":
                move(pos, voucher, "In Progress", "Preparation Started", voucher.name)
            return

        notes = submitted_outbound(reference)
        if event == "cancel" and current in ("Out for Delivery", "Delivered"):
            review(pos, voucher, event, "An outbound Delivery Note was cancelled. Review the recorded delivery.")
            return
        if len(notes) > 1:
            review(pos, voucher, event, "Multiple submitted outbound Delivery Notes are linked. Stock Manager reconciliation is required.")
            return
        if not notes:
            if event == "cancel" and current == "To Deliver":
                move(pos, voucher, "In Progress", "Delivery Note Cancelled", voucher.name)
            return
        remaining = notes[0]
        if not is_eligible_dn(remaining, pos) or has_stock_return(remaining.name):
            review(pos, voucher, event, "The submitted outbound Delivery Note is ineligible. Stock Manager reconciliation is required.")
            return
        if current not in ("Pending", "In Progress"):
            return
        if event == "submit" and remaining.name == voucher.name:
            move(pos, voucher, "To Deliver", "Delivery Note Submitted", remaining.name)
        elif event == "cancel" and frappe.db.exists("Comment", {
            "reference_doctype": "POS Upload", "reference_name": pos.name, "comment_type": "Workflow",
            "content": ["like", "POS delivery review · submit · % · Multiple submitted outbound Delivery Notes are linked.%"],
        }):
            move(pos, voucher, "To Deliver", "Delivery Note Conflict Resolved", remaining.name)


    def handle_stock_entry(voucher, event):
        reference = voucher.custom_reference_no or ""
        if voucher.company != "Multimax" or voucher.purpose != "Material Issue" or not reference.startswith(("MX-", "KX-")):
            return
        if voucher.get("is_return") or not frappe.db.get_value("POS Upload", reference, "name", for_update=True):
            return
        pos = frappe.get_doc("POS Upload", reference, for_update=True)
        current = pos.status or "Pending"
        if event == "save":
            amended = None
            if current == "Cancelled" and voucher.amended_from:
                amended = frappe.db.get_value("Stock Entry", {
                    "name": voucher.amended_from, "company": "Multimax", "purpose": "Material Issue",
                    "docstatus": 2, "custom_reference_no": reference,
                }, "name", for_update=True)
            if current == "Pending" or amended:
                move(pos, voucher, "In Progress", "Preparation Started")
        elif event == "submit" and current in ("Pending", "In Progress", "Cancelled"):
            move(pos, voucher, "Completed", "Material Issue Submitted")
        elif event == "cancel" and current in ("In Progress", "Completed"):
            sibling = frappe.db.get_value("Stock Entry", {
                "company": "Multimax", "purpose": "Material Issue", "docstatus": 1, "custom_reference_no": reference,
            }, "name", for_update=True)
            if not sibling:
                move(pos, voucher, "Cancelled", "Material Issue Cancelled")


    if voucher.docstatus != expected_docstatus:
        return
    if voucher.doctype == "Delivery Note":
        handle_dn(voucher, event)
    elif voucher.doctype == "Stock Entry":
        handle_stock_entry(voucher, event)


handle_voucher(doc, event, expected_docstatus)
