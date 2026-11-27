# Server Script (API) mobile_push_mark_invalid — the sender reports a token FCM rejected (uninstalled app, bad token).
# Args: device (Mobile Push Device name), error (FCM error text). System Manager only.
if not frappe.db.exists("Has Role", {"parent": frappe.session.user, "parenttype": "User", "role": "System Manager"}):
    frappe.throw("Not permitted", frappe.PermissionError)

device = frappe.form_dict.get("device")
if not device or not frappe.db.exists("Mobile Push Device", device):
    frappe.throw("Unknown device.")
frappe.db.set_value("Mobile Push Device", device, {
    "enabled": 0,
    "last_error": (frappe.form_dict.get("error") or "Rejected by FCM")[:1000],
})
frappe.response["message"] = {"device": device}
