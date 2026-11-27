# Server Script (API) mobile_push_recipients — the sender (n8n) asks which phones should get an alert.
# Args: roles (comma-separated role names), exclude (optional user, e.g. whoever recorded the action).
# Returns enabled devices of enabled users holding any of the roles. Tokens are sensitive, so System Manager only.
if not frappe.db.exists("Has Role", {"parent": frappe.session.user, "parenttype": "User", "role": "System Manager"}):
    frappe.throw("Not permitted", frappe.PermissionError)

roles = [r.strip() for r in (frappe.form_dict.get("roles") or "").split(",") if r.strip()]
if not roles:
    frappe.throw("roles is required.")
exclude = frappe.form_dict.get("exclude") or ""

holders = set(frappe.get_all("Has Role", filters={"role": ["in", roles], "parenttype": "User"}, pluck="parent"))
users = set(frappe.get_all("User", filters={"name": ["in", list(holders) or [""]], "enabled": 1}, pluck="name"))
users.discard(exclude)

devices = []
if users:
    devices = frappe.get_all(
        "Mobile Push Device",
        filters={"enabled": 1, "user": ["in", list(users)]},
        fields=["name", "user", "token", "platform", "app_id"],
    )
frappe.response["message"] = devices
