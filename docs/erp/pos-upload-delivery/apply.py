#!/usr/bin/env python3
"""Capture and manage the POS Upload delivery configuration using Frappe REST."""

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


ROOT = Path(__file__).resolve().parent
STAGING = "https://erp-testing.multimax.cloud"
LIVE = "https://erp.multimax.cloud"
SERVER_SCRIPTS_ENABLED = "/api/method/frappe.core.doctype.server_script.server_script.enabled"
PERMISSIONS = "/api/method/frappe.core.page.permission_manager.permission_manager."
PHASES = ("configuration", "workflow", "webhook")
VOUCHER_SCRIPTS = tuple(
    f"{voucher} updates POS Upload {state}"
    for voucher in ("Delivery Note", "Stock Entry")
    for state in ("In Progress", "Completed", "Cancelled")
)
SCOPES = (
    ("Property Setter", {"doc_type": "POS Upload"}),
    ("Custom Field", {"dt": "POS Upload"}),
    ("Client Script", {"dt": "POS Upload"}),
    ("Custom DocPerm", {"parent": "POS Upload"}),
    ("Custom DocPerm", {"parent": "Driver"}),
    ("Workflow", {"document_type": "POS Upload"}),
)
CAPTURE_ONLY = (("Webhook", "POS Upload"),)
PERMISSION_RIGHTS = (
    "select", "read", "write", "create", "delete", "submit", "cancel", "amend",
    "print", "email", "report", "import", "export", "share", "mask",
)
METADATA = {
    "name", "owner", "creation", "modified", "modified_by", "docstatus", "idx",
    "parentfield", "parenttype", "_user_tags", "_comments", "_assign", "_liked_by",
}
REDACTED = "[REDACTED]"
SECRET_FIELD = re.compile(
    r"^(?:authorization|password|passphrase|api[_-]?(?:key|secret|token)|"
    r"(?:access|refresh|bot|bearer)[_-]?token|(?:client|webhook|hmac)[_-]?secret|"
    r"signing[_-]?secret|secret(?:[_-]?key)?|token|private[_-]?key|cookie|x-api-key)$", re.I
)
SECRET_TEXT = re.compile(
    r"(?i)(\b(?:authorization|password|passphrase|api[_-]?(?:key|secret|token)|"
    r"(?:access|refresh|bot|bearer)[_-]?token|(?:client|webhook|hmac)[_-]?secret|"
    r"signing[_-]?secret|secret(?:[_-]?key)?|token|private[_-]?key|x-api-key)\s*['\"]?\s*[:=]\s*)"
    r"(['\"])([^'\"\r\n]+)\2"
)
TOKEN_TEXT = re.compile(
    r"(?i)\b(?:token\s+[a-z0-9_-]{8,}:[a-z0-9_-]{8,}|"
    r"bearer\s+[a-z0-9._~+/-]{12,}|\d{7,12}:[a-z0-9_-]{25,}|"
    r"[a-z0-9_-]{14,}:[a-z0-9_-]{14,})(?=$|\W)"
)
URL_USERINFO = re.compile(r"(?i)(https?://)[^/@\s]+:[^/@\s]+@")
URL_SECRET = re.compile(r"(?i)([?&](?:api[_-]?key|(?:access[_-]?)?token|secret|password)=)[^&\s'\"]+")
PRIVATE_KEY = re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----", re.S)


class RolloutError(Exception):
    """A safe operator-facing diagnostic."""


class ApiError(RolloutError):
    def __init__(self, status, exc_type=""):
        self.status = status
        self.exc_type = exc_type
        note = f" ({exc_type})" if exc_type else ""
        if status == 401:
            super().__init__("HTTP 401. Stop and verify whether the ERP key was rotated.")
        else:
            super().__init__(f"ERP request failed with HTTP {status}{note}.")


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def read_key(path):
    content = Path(path).read_text(encoding="utf-8-sig")
    matches = re.findall(r"(?m)^\s*`([^`\s:]+:[^`\s:]+)`\s*$", content)
    if len(matches) != 1:
        raise RolloutError("The key file must contain one standalone backticked key:secret line.")
    return matches[0]


def sanitize(value, known=()):
    """Return a persistence-safe document and indicate which keys were redacted."""
    paths = []

    def clean(node, path, redact=False):
        if redact and node:
            paths.append(path)
            return REDACTED
        if isinstance(node, dict):
            is_secret_header = SECRET_FIELD.fullmatch(str(node.get("key", "")))
            return {
                key: clean(child, f"{path}.{key}" if path else key,
                           bool(SECRET_FIELD.fullmatch(key)) or (is_secret_header and key == "value"))
                for key, child in node.items()
            }
        if isinstance(node, list):
            return [clean(child, f"{path}[{index}]") for index, child in enumerate(node)]
        if isinstance(node, str):
            text = node
            for secret in known:
                if secret:
                    text = text.replace(secret, REDACTED)
            text = SECRET_TEXT.sub(lambda m: m[1] + m[2] + REDACTED + m[2], text)
            text = TOKEN_TEXT.sub(REDACTED, text)
            text = URL_USERINFO.sub(r"\1" + REDACTED + "@", text)
            text = URL_SECRET.sub(r"\1" + REDACTED, text)
            text = PRIVATE_KEY.sub(REDACTED, text)
            if text != node:
                paths.append(path)
            return text
        return node

    return clean(value, ""), paths


def resource(doctype, name=None):
    path = "/api/resource/" + quote(doctype, safe="")
    return path if name is None else path + "/" + quote(name, safe="")


class Api:
    def __init__(self, url, key_path, *, authorize_live_cutover=False):
        self.url = url.rstrip("/")
        if self.url not in (STAGING, LIVE):
            raise RolloutError("Use the Multimax staging or live HTTPS origin as --url.")
        self._writable = self.url == STAGING or authorize_live_cutover
        self._token = read_key(key_path)
        self._opener = build_opener(NoRedirect())

    def redact(self, value):
        return sanitize(value, (self._token, *self._token.split(":")))

    def request(self, method, path, payload=None, query=None):
        if method != "GET" and not self._writable:
            raise RolloutError("Live writes require separate cutover authorization.")
        parsed = urlsplit(path)
        if not path.startswith("/api/") or parsed.netloc or parsed.scheme or parsed.query or parsed.fragment:
            raise RolloutError("Expected a relative Frappe API path.")
        suffix = "?" + urlencode(query) if query else ""
        request = Request(
            self.url + path + suffix,
            data=json.dumps(payload, ensure_ascii=False).encode("utf-8") if payload is not None else None,
            headers={
                "Authorization": "token " + self._token,
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
            method=method,
        )
        try:
            with self._opener.open(request, timeout=45) as response:
                return json.load(response)
        except HTTPError as error:
            failure = ""
            if error.code != 401:
                try:
                    value = json.load(error).get("exc_type", "")
                    if isinstance(value, str) and re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]{0,79}", value):
                        failure = self.redact(value)[0]
                except (ValueError, AttributeError):
                    pass
            raise ApiError(error.code, failure) from None
        except (URLError, OSError):
            raise RolloutError("ERP connection failed. Re-run the dry run to inspect the current state.") from None
        except ValueError:
            raise RolloutError("ERP returned an unreadable response.") from None

    def get(self, doctype, name):
        try:
            return self.request("GET", resource(doctype, name))["data"]
        except ApiError as error:
            if error.status == 404:
                return None
            raise

    def list(self, doctype, filters, fields=None):
        records = []
        while True:
            page = self.request("GET", resource(doctype), query={
                "filters": json.dumps(filters),
                "fields": json.dumps(fields or ["name"]),
                "order_by": "name asc",
                "limit_start": len(records),
                "limit_page_length": 100,
            })["data"]
            records.extend(page)
            if len(page) < 100:
                return records

    def preflight(self):
        if self.request("GET", SERVER_SCRIPTS_ENABLED).get("message") is not True:
            raise RolloutError("ERP did not confirm that Server Scripts are enabled. Stop before applying.")


def doc_key(record):
    return record["doctype"], record["name"]


def load_records(directory=ROOT / "records"):
    pending = {}
    for path in sorted(directory.glob("*.json")):
        record = json.loads(path.read_text(encoding="utf-8-sig"))
        fields = set(record)
        if {key for key in fields if key.startswith("_")} - {"_script_file", "_script_include", "_depends", "_if_missing"}:
            raise RolloutError(f"Unknown rollout option in {path.name}.")
        for key in ("_script_file", "_script_include"):
            if key in record:
                script = (path.parent / record.pop(key)).resolve()
                if not script.is_relative_to(ROOT):
                    raise RolloutError(f"Script path in {path.name} must stay in the rollout directory.")
                source = script.read_text(encoding="utf-8-sig")
                record["script"] = (record.get("script", "") + "\n" + source).lstrip("\n")
        key = doc_key(record)
        if key in pending:
            raise RolloutError(f"Duplicate rollout record in {path.name}.")
        if key[0] == "Webhook" and record.get("enabled") != 0:
            raise RolloutError("The staging webhook must be disabled in source.")
        if key[0] == "Workflow" and record.get("send_email_alert") != 0:
            raise RolloutError("Workflow email alerts must be disabled in source.")
        pending[key] = record
    ordered = {}
    while pending:
        next_key = next((key for key, record in pending.items()
                         if all(tuple(dependency) in ordered for dependency in record.get("_depends", []))), None)
        if next_key is None:
            raise RolloutError("Unresolved rollout dependencies. Check the _depends references.")
        ordered[next_key] = pending.pop(next_key)
    return sorted(ordered.values(), key=lambda record: PHASES.index(record_phase(record)))


def record_phase(record):
    return {"Workflow": "workflow", "Webhook": "webhook"}.get(record["doctype"], "configuration")


def permission_identity(record):
    return {
        "parent": record["parent"],
        "role": record["role"],
        "permlevel": int(record.get("permlevel") or 0),
        "if_owner": int(record.get("if_owner") or 0),
    }


def current_record(api, record):
    doctype, name = doc_key(record)
    if doctype == "Custom DocPerm":
        identity = permission_identity(record)
        peers = api.list(doctype, {key: value for key, value in identity.items() if key != "if_owner"},
                         fields=["name", "if_owner"])
        if len(peers) > 1:
            raise RolloutError(f"Ambiguous Custom DocPerm rows for {identity['parent']} / {identity['role']}.")
        if peers and int(peers[0].get("if_owner") or 0) != identity["if_owner"]:
            raise RolloutError(f"Pre-existing owner-only Custom DocPerm conflicts with {name}.")
        return api.get(doctype, peers[0]["name"]) if peers else None
    return api.get(doctype, name)


def snapshot_name(doctype, name):
    return re.sub(r"[^A-Za-z0-9_-]", "-", f"{doctype}--{name}").lower() + ".json"


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")


def capture(api, records, before_dir):
    manifest_path = before_dir / "manifest.json"
    if manifest_path.exists():
        raise RolloutError("Before-images already exist. Preserve the original capture for rollback.")
    docs = {}
    for doctype, filters in SCOPES:
        for row in api.list(doctype, filters):
            doc = api.get(doctype, row["name"])
            if doc is None:
                raise RolloutError(f"{doctype} changed during capture. Repeat before any writes.")
            docs[doc_key(doc)] = doc
    for name in VOUCHER_SCRIPTS:
        doc = api.get("Server Script", name)
        if doc is None:
            raise RolloutError(f"Required existing Server Script missing: {name}.")
        docs[doc_key(doc)] = doc
    for doctype, name in CAPTURE_ONLY:
        doc = api.get(doctype, name)
        if doc is not None:
            docs[doc_key(doc)] = doc
    for record in records:
        doc = current_record(api, record)
        if doc is not None:
            docs[doc_key(doc)] = doc

    permission_baseline = {}
    for parent in ("POS Upload", "Driver"):
        baseline = api.request("GET", PERMISSIONS + "get_standard_permissions", query={"doctype": parent})
        permission_baseline[parent] = api.redact(baseline["message"])[0]

    save_before_images(api, docs, permission_baseline, before_dir)


def save_before_images(api, docs, permission_baseline, before_dir):
    manifest_path = before_dir / "manifest.json"
    before_dir.mkdir(parents=True, exist_ok=True)
    entries = []
    used_paths = set()
    for (doctype, name), doc in sorted(docs.items()):
        safe, redactions = api.redact(doc)
        if doc_key(safe) != (doctype, name):
            raise RolloutError("A captured record identifier appears to contain a credential.")
        filename = snapshot_name(doctype, name)
        if filename in used_paths:
            raise RolloutError("Two before-images have the same filename. Resolve the collision before applying.")
        used_paths.add(filename)
        write_json(before_dir / filename, safe)
        entries.append({"doctype": doctype, "name": name, "file": filename, "redactions": redactions})

    write_json(manifest_path, {
        "origin": api.url,
        "captured_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "records": entries,
        "standard_permissions": permission_baseline,
    })
    print(f"Captured {len(entries)} before-images. Redacted fields: {sum(len(row['redactions']) for row in entries)}.")


def load_before(api, before_dir):
    path = before_dir / "manifest.json"
    if not path.is_file():
        raise RolloutError("Capture the target site's before-images before running this operation.")
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest["origin"] != api.url:
        raise RolloutError("Before-images belong to a different ERP site.")
    docs = {}
    for entry in manifest["records"]:
        key = doc_key(entry)
        if entry["file"] != snapshot_name(*key) or key in docs:
            raise RolloutError("Invalid before-image entry.")
        doc = json.loads((before_dir / entry["file"]).read_text(encoding="utf-8"))
        if doc_key(doc) != key:
            raise RolloutError("Before-image identity differs from its manifest.")
        docs[key] = doc
    for name in VOUCHER_SCRIPTS:
        if ("Server Script", name) not in docs:
            raise RolloutError(f"Capture is missing the before-image for {name}.")
    return docs, manifest.get("standard_permissions", {})


def writable(record, child=False):
    if isinstance(record, dict):
        return {
            key: writable(value, child=True) for key, value in record.items()
            if key not in METADATA and not key.startswith("_") and (not child or key != "parent")
        }
    if isinstance(record, list):
        return [writable(item, child=True) for item in record]
    return record


def matches(actual, desired):
    if isinstance(desired, dict):
        return isinstance(actual, dict) and all(matches(actual.get(key), value) for key, value in desired.items())
    if isinstance(desired, list):
        return (isinstance(actual, list) and len(actual) == len(desired)
                and all(matches(left, right) for left, right in zip(actual, desired)))
    if actual in (None, "") and desired in (None, ""):
        return True
    if isinstance(actual, (int, str)) and isinstance(desired, (int, str)):
        if str(actual).isdecimal() and str(desired).isdecimal():
            return int(actual) == int(desired)
        return str(actual).replace("\r\n", "\n") == str(desired).replace("\r\n", "\n")
    return actual == desired


def desired_fields(record):
    fields = writable(record)
    fields.pop("doctype", None)
    return fields


def comparable(record, fields):
    if record["doctype"] == "Webhook":
        return {key: value for key, value in fields.items() if key != "webhook_secret"}
    return fields


def before_record(before, record):
    if record["doctype"] == "Custom DocPerm":
        identity = permission_identity(record)
        for doc in before.values():
            if doc["doctype"] == "Custom DocPerm" and permission_identity(doc) == identity:
                return doc
        return None
    return before.get(doc_key(record))


def label(record):
    return f"{record['doctype']} / {record['name']}"


def check_compilation(api, response):
    messages = response.get("_server_messages")
    if not messages:
        return
    if isinstance(messages, str):
        messages = json.loads(messages)
    for message in messages:
        if isinstance(message, str):
            message = json.loads(message)
        if message.get("title") == "Compilation warning":
            detail = api.redact(str(message.get("message", "")))[0][:400]
            raise RolloutError(f"Frappe reported a Server Script compilation warning: {detail}")


def put_document(api, record, current, fields):
    doctype, name = doc_key(record)
    if current is None:
        response = api.request("POST", resource(doctype), {"name": name, **fields})
    else:
        response = api.request("PUT", resource(doctype, current["name"]), {"modified": current["modified"], **fields})
    if doctype == "Server Script":
        check_compilation(api, response)
    if response.get("data", {}).get("name") != name:
        raise RolloutError(f"ERP assigned an unexpected name to {label(record)}. Review before retrying.")


def put_permission(api, record, current, fields):
    identity = permission_identity(record)
    if identity["if_owner"] != 0:
        raise RolloutError(f"Rollout rule must be unrestricted by owner: {label(record)}.")
    if current is None:
        api.request("POST", PERMISSIONS + "add", {key: identity[key] for key in ("parent", "role", "permlevel")})
        current = current_record(api, record)
        if current is None:
            raise RolloutError(f"ERP did not create {label(record)}.")
    for right in PERMISSION_RIGHTS:
        if right in fields and not matches(current.get(right), fields[right]):
            api.request("POST", PERMISSIONS + "update", {
                "doctype": identity["parent"], "role": identity["role"], "permlevel": identity["permlevel"],
                "ptype": right, "value": fields[right], "if_owner": 0,
            })


def put(api, record, current, fields):
    try:
        if record["doctype"] == "Custom DocPerm":
            put_permission(api, record, current, fields)
        else:
            put_document(api, record, current, fields)
    except ApiError as error:
        if error.status == 401:
            raise
        raise RolloutError(f"{label(record)}. {error}") from None
    result = current_record(api, record)
    expected = comparable(record, fields)
    differences = [key for key, value in expected.items() if not matches((result or {}).get(key), value)]
    if result is None or differences:
        raise RolloutError(f"ERP did not persist {label(record)} fields: {', '.join(differences)}.")


def apply_plan(api, records, before, dry_run):
    # Resolve all targets before the first write, including logical permission keys.
    plan = [(record, current_record(api, record)) for record in records]
    new_workflow = any(record["doctype"] == "Workflow" and record.get("is_active") for record in records)
    if new_workflow:
        known = {name for doctype, name in before if doctype == "Workflow"}
        known.update(record["name"] for record in records if record["doctype"] == "Workflow")
        active = api.list("Workflow", {"document_type": "POS Upload", "is_active": 1})
        if any(row["name"] not in known for row in active):
            raise RolloutError("An active POS Upload Workflow appeared after the before-image capture.")

    changes = 0
    for record, current in plan:
        fields = desired_fields(record)
        if current is not None and (record.get("_if_missing") or matches(current, comparable(record, fields))):
            print(f"Keep {label(record)}")
            continue
        previous = before_record(before, record)
        if previous is not None and current is None:
            raise RolloutError(f"A captured record disappeared: {label(record)}.")
        if previous is not None and any(REDACTED in json.dumps(previous.get(key)) for key in fields):
            raise RolloutError(f"A redacted before-image prevents safe replacement of {label(record)}.")
        action = "Create" if current is None else "Update"
        print(f"{action} {label(record)}", flush=True)
        if not dry_run:
            # Role Permission Manager can materialize standard rows on the first insert.
            if record["doctype"] == "Custom DocPerm":
                current = current_record(api, record)
            put(api, record, current, fields)
        changes += 1
    print(f"{changes} {'planned' if dry_run else 'applied'} changes.")


def restore_fields(record, previous):
    original = writable(previous)
    fields = {key: original.get(key) for key in desired_fields(record)}
    if any(REDACTED in json.dumps(value) for value in fields.values()):
        raise RolloutError(f"A redacted before-image requires manual restoration of {label(record)}.")
    return fields


def deactivate(api, record, field, value):
    current = current_record(api, record)
    if current is not None and not matches(current.get(field), value):
        print(f"Disable {label(record)}", flush=True)
        put(api, record, current, {field: value})


def remove_permission(api, identity):
    api.request("POST", PERMISSIONS + "remove", identity)


def reset_seeded_permissions(api, parent, records, baseline):
    current = api.list("Custom DocPerm", {"parent": parent}, fields=["name", "role", "permlevel", "if_owner"])
    if not current:
        return
    allowed = [permission_identity({**doc, "parent": parent}) for doc in baseline]
    allowed.extend(permission_identity(doc) for doc in records)
    for row in current:
        identity = permission_identity({**row, "parent": parent})
        if identity not in allowed:
            raise RolloutError(f"New unrelated Custom DocPerm on {parent}; review before resetting permissions.")
        candidates = [doc for doc in baseline if permission_identity({**doc, "parent": parent}) == identity]
        candidates.extend(doc for doc in records if permission_identity(doc) == identity)
        actual = api.get("Custom DocPerm", row["name"])
        for right in PERMISSION_RIGHTS:
            bits = [int(doc.get(right) or 0) for doc in candidates]
            if identity not in [permission_identity({**doc, "parent": parent}) for doc in baseline] and right in ("read", "export"):
                bits.append(1)  # Defaults while a newly added rule is being configured.
            if int(actual.get(right) or 0) not in bits:
                raise RolloutError(f"Custom DocPerm rights changed on {parent}; review before resetting permissions.")
    print(f"Restore standard permissions on {parent}", flush=True)
    api.request("POST", PERMISSIONS + "reset", {"doctype": parent})
    if api.list("Custom DocPerm", {"parent": parent}):
        raise RolloutError(f"ERP did not reset permissions on {parent}.")


def rollback(api, records, before, baseline):
    for doctype, field, value in (("Webhook", "enabled", 0), ("Workflow", "is_active", 0), ("Server Script", "disabled", 1)):
        for record in records:
            if record["doctype"] != doctype:
                continue
            previous = before.get(doc_key(record))
            if previous is not None:
                if doctype == "Server Script":
                    continue
                current = current_record(api, record)
                restored = restore_fields(record, previous)
                if matches(current, comparable(record, restored)):
                    continue
            deactivate(api, record, field, value)

    permission_parents = {record["parent"] for record in records if record["doctype"] == "Custom DocPerm"}
    reset_parents = permission_parents - {doc["parent"] for doc in before.values() if doc["doctype"] == "Custom DocPerm"}
    for parent in sorted(reset_parents):
        affected = [record for record in records if record["doctype"] == "Custom DocPerm" and record["parent"] == parent]
        reset_seeded_permissions(api, parent, affected, baseline[parent])

    retained = {"Custom Field", "Role", "Workflow State", "Workflow Action Master", "Workflow Transition Tasks",
                "Workflow", "Webhook", "Server Script"}
    for record in reversed(records):
        doctype, name = doc_key(record)
        if doctype == "Property Setter" and record.get("field_name") == "status" and record.get("property") == "options":
            continue  # Keep fields that existing delivery history depends on.
        if doctype == "Custom DocPerm" and record["parent"] in reset_parents:
            continue
        previous = before_record(before, record)
        current = current_record(api, record)
        if previous is None:
            if current is None or doctype in retained:
                continue
            print(f"Remove {label(record)}", flush=True)
            if doctype == "Custom DocPerm":
                remove_permission(api, permission_identity(record))
            else:
                api.request("DELETE", resource(doctype, name))
            if current_record(api, record) is not None:
                raise RolloutError(f"ERP did not remove {label(record)}.")
        elif not record.get("_if_missing"):
            fields = restore_fields(record, previous)
            if not matches(current, comparable(record, fields)):
                print(f"Restore {label(record)}", flush=True)
                put(api, record, current, fields)

    # Frappe automatically deactivates the previous Workflow during activation.
    targeted = {doc_key(record) for record in records}
    for key, previous in before.items():
        if key[0] == "Workflow" and key not in targeted and previous.get("is_active"):
            current = current_record(api, previous)
            if current is None:
                raise RolloutError(f"Prior Workflow missing: {label(previous)}.")
            if not current.get("is_active"):
                print(f"Restore active {label(previous)}", flush=True)
                put(api, previous, current, {"is_active": 1})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--capture", action="store_true", help="save original configuration with GETs only")
    modes.add_argument("--dry-run", action="store_true", help="show planned changes with GETs only")
    modes.add_argument("--apply", action="store_true", help="create or update delivery records")
    modes.add_argument("--rollback", action="store_true", help="use the before-images to pause and restore configuration")
    parser.add_argument("--url", default=os.getenv("POS_DELIVERY_ERP_URL"), required=not os.getenv("POS_DELIVERY_ERP_URL"))
    parser.add_argument("--key-path", default=os.getenv("POS_DELIVERY_ERP_KEY_PATH"), required=not os.getenv("POS_DELIVERY_ERP_KEY_PATH"))
    parser.add_argument("--before-dir", type=Path, help="directory for the target site's before-images")
    parser.add_argument("--phase", choices=PHASES, help="select a phase for apply or dry run")
    parser.add_argument("--authorize-live-cutover", action="store_true",
                        help="opt in to live apply or rollback only after separate approval")
    args = parser.parse_args()
    try:
        live = args.url.rstrip("/") == LIVE
        write_mode = args.apply or args.rollback
        if args.authorize_live_cutover and not (live and write_mode):
            raise RolloutError("--authorize-live-cutover requires live --apply or --rollback.")
        if live and write_mode and not args.authorize_live_cutover:
            raise RolloutError("Live writes require separate cutover authorization.")
        if args.phase and not (args.apply or args.dry_run):
            raise RolloutError("--phase requires --apply or --dry-run.")
        if live and args.apply and not args.phase:
            raise RolloutError("Live apply requires one explicit phase.")
        if live and write_mode and args.before_dir is None:
            raise RolloutError("Live writes require an explicit path to the fresh live before-images.")
        api = Api(args.url, args.key_path, authorize_live_cutover=args.authorize_live_cutover)
        before_dir = args.before_dir or ROOT / "before" / ("staging" if api.url == STAGING else "live")
        records = load_records()
        if args.phase:
            records = [record for record in records if record_phase(record) == args.phase]
        if not records and not args.capture:
            raise RolloutError("No rollout records found in records/.")
        api.preflight()
        if args.capture:
            capture(api, records, before_dir)
        else:
            before, baseline = load_before(api, before_dir)
            if args.rollback:
                rollback(api, records, before, baseline)
            else:
                apply_plan(api, records, before, args.dry_run)
    except (RolloutError, OSError, KeyError, ValueError) as error:
        # File contents, request bodies and headers are never written to diagnostics.
        if isinstance(error, RolloutError):
            print(error, file=sys.stderr)
        else:
            print(f"Rollout stopped while reading its inputs or ERP response ({type(error).__name__}).", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
