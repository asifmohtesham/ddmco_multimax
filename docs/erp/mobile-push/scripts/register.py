# Server Script (API) mobile_push_register — the signed-in app user registers (or re-claims) a push token.
# A token belongs to one install; if another user signed in on that phone before, the row moves to this user.
user = frappe.session.user
if user == "Guest":
    frappe.throw("Sign in to register for notifications.", frappe.PermissionError)

token = (frappe.form_dict.get("token") or "").strip()
if not token or len(token) > 255:
    frappe.throw("A valid push token is required.")
platform = frappe.form_dict.get("platform")
if platform not in ("android", "ios"):
    frappe.throw("Unknown platform.")

values = {
    "user": user,
    "enabled": 1,
    "platform": platform,
    "app_id": (frappe.form_dict.get("app_id") or "")[:140],
    "app_version": (frappe.form_dict.get("app_version") or "")[:140],
    "device_model": (frappe.form_dict.get("device_model") or "")[:140],
    "last_seen": frappe.utils.now(),
    "last_error": None,
}
name = frappe.db.get_value("Mobile Push Device", {"token": token})
if name:
    frappe.db.set_value("Mobile Push Device", name, values)
else:
    values["doctype"] = "Mobile Push Device"
    values["token"] = token
    doc = frappe.get_doc(values)
    doc.insert(ignore_permissions=True)
    name = doc.name

frappe.response["message"] = {"device": name}
