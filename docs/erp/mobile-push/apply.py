#!/usr/bin/env python3
"""Create or update the Mobile Push Device DocType and its two API Server Scripts.

Usage:  ERP_KEY=<key>:<secret> python apply.py --site staging|live [--dry-run]

Every record that exists is saved to before/<site>-<timestamp>/ before it changes, so a rollback is
"PUT the before-image back" (or DELETE a record that had none).
"""

import argparse
import json
import os
import sys
from datetime import datetime
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent
SITES = {"staging": "https://erp-testing.multimax.cloud", "live": "https://erp.multimax.cloud"}
SERVER_SCRIPTS = (
    ("Mobile Push Register", "mobile_push_register", "register.py"),
    ("Mobile Push Unregister", "mobile_push_unregister", "unregister.py"),
    ("Mobile Push Recipients", "mobile_push_recipients", "recipients.py"),
    ("Mobile Push Mark Invalid", "mobile_push_mark_invalid", "mark-invalid.py"),
)
METADATA = {"owner", "creation", "modified", "modified_by", "docstatus", "idx", "_user_tags",
            "_comments", "_assign", "_liked_by", "doctype", "name", "parent", "parentfield", "parenttype"}


def records():
    yield json.loads((ROOT / "records" / "01-doctype-mobile-push-device.json").read_text(encoding="utf-8"))
    for name, method, path in SERVER_SCRIPTS:
        yield {"doctype": "Server Script", "name": name, "script_type": "API", "api_method": method,
               "allow_guest": 0, "disabled": 0,
               "script": (ROOT / "scripts" / path).read_text(encoding="utf-8")}


def call(base, key, method, path, body=None):
    req = Request(base + path, method=method, data=None if body is None else json.dumps(body).encode(),
                  headers={"Authorization": f"token {key}", "Accept": "application/json",
                           "Content-Type": "application/json"})
    try:
        with urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except HTTPError as e:
        return e.code, json.loads(e.read() or b"{}") if e.headers.get_content_type() == "application/json" else {}


def differs(want, have):
    for k, v in want.items():
        if k in METADATA:
            continue
        if k in ("fields", "permissions"):
            strip = lambda rows: [{f: r.get(f) for f in row} for row, r in zip(want[k], rows)]
            if len(have.get(k) or []) != len(v) or strip(have[k]) != v:
                return True
        elif str(have.get(k) if have.get(k) is not None else "") != str(v if v is not None else ""):
            return True
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--site", choices=SITES, required=True)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    key = os.environ.get("ERP_KEY")
    if not key:
        sys.exit("Set ERP_KEY=<api key>:<api secret>")
    base = SITES[args.site]
    before = ROOT / "before" / f"{args.site}-{datetime.now():%Y%m%d-%H%M%S}"
    for rec in records():
        path = f"/api/resource/{quote(rec['doctype'])}/{quote(rec['name'])}"
        status, body = call(base, key, "GET", path)
        if status == 404:
            print(f"create  {rec['doctype']}: {rec['name']}")
            if not args.dry_run:
                status, body = call(base, key, "POST", f"/api/resource/{quote(rec['doctype'])}", rec)
                if status != 200:
                    sys.exit(f"  failed {status}: {body.get('exception') or body}")
            continue
        if status != 200:
            sys.exit(f"GET {path} -> {status}")
        have = body["data"]
        if not differs(rec, have):
            print(f"same    {rec['doctype']}: {rec['name']}")
            continue
        print(f"update  {rec['doctype']}: {rec['name']}")
        if not args.dry_run:
            before.mkdir(parents=True, exist_ok=True)
            (before / f"{rec['doctype']}-{rec['name']}.json".replace(" ", "_")).write_text(
                json.dumps(have, indent=2, ensure_ascii=False), encoding="utf-8")
            status, body = call(base, key, "PUT", path, {**rec, "modified": have["modified"]})
            if status != 200:
                sys.exit(f"  failed {status}: {body.get('exception') or body}")


if __name__ == "__main__":
    main()
