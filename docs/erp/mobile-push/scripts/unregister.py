# Server Script (API) mobile_push_unregister — called on sign-out so the phone stops receiving this user's alerts.
# Only the caller's own row is touched; an unknown token is not an error.
token = (frappe.form_dict.get("token") or "").strip()
name = None
if token:
    name = frappe.db.get_value("Mobile Push Device", {"token": token, "user": frappe.session.user})
if name:
    frappe.db.set_value("Mobile Push Device", name, {"enabled": 0, "last_seen": frappe.utils.now()})

frappe.response["message"] = {"device": name}
