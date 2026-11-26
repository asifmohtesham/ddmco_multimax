#!/usr/bin/env python3
"""Check an approved cutover enrolment list with GETs and render an ERP console batch."""

import argparse
import json
import os
import sys
from datetime import datetime
from pathlib import Path

from apply import Api, ROOT, RolloutError, load_records, matches


DN_SUBMIT_SCRIPT = "Delivery Note updates POS Upload Completed"
OPEN_STATUSES = (None, "", "Pending", "In Progress")
VOUCHER_CALL = "handle_voucher(doc, event, expected_docstatus)"


def read_candidates(path):
    rows = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(rows, list):
        raise RolloutError("The approved list must be a JSON array.")
    seen = set()
    for row in rows:
        if (not isinstance(row, dict) or set(row) != {"pos", "dn", "modified"}
                or any(not isinstance(value, str) or not value.strip() for value in row.values())):
            raise RolloutError("Each approved row must have POS, DN and modified strings under pos, dn and modified.")
        if row["pos"] in seen:
            raise RolloutError("Each approved POS may appear only once.")
        seen.add(row["pos"])
        datetime.fromisoformat(row["modified"])
    return sorted(rows, key=lambda row: row["pos"])


def review(api, row):
    pos = api.get("POS Upload", row["pos"])
    if pos is None or pos["name"] != row["pos"]:
        return "POS Upload not found by exact name"
    if not (pos["name"].startswith(("ML-", "KA-")) and pos["docstatus"] == 0 and pos.get("status") in OPEN_STATUSES):
        return "POS is outside the open ML/KA delivery path"
    if datetime.fromisoformat(pos["modified"]) != datetime.fromisoformat(row["modified"]):
        return "POS revision changed"

    notes = api.list("Delivery Note", {"po_no": pos["name"], "docstatus": 1, "is_return": 0},
                     ["name", "po_no", "company", "customer", "total_qty"])
    if len(notes) != 1:
        return f"{len(notes)} submitted outbound Delivery Notes"
    dn = notes[0]
    if dn["name"] != row["dn"] or dn["po_no"] != pos["name"]:
        return "submitted Delivery Note does not match the approved pair exactly"
    if dn["company"] != "Multimax" or dn["customer"] != pos["customer"] or not (float(dn["total_qty"] or 0) > 0):
        return "submitted Delivery Note needs Multimax, the POS customer and positive quantity"
    if api.list("Delivery Note", {"return_against": dn["name"], "docstatus": 1, "is_return": 1}):
        return "a submitted stock return exists"
    return None


def render_console(api, rows, target):
    expected = next(record for record in load_records() if record["doctype"] == "Server Script"
                    and record["name"] == DN_SUBMIT_SCRIPT)
    installed = api.get("Server Script", DN_SUBMIT_SCRIPT) or {}
    if not matches(installed, {"script": expected["script"], "disabled": 0}):
        raise RolloutError("The enabled DN-submit script on ERP differs from the reviewed source.")
    handler, marker, after = expected["script"].rpartition(VOUCHER_CALL)
    if not marker or after.strip():
        raise RolloutError("The reviewed DN-submit source has an unexpected invocation.")

    batch = (ROOT / "scripts" / "enrol-cutover.py").read_text(encoding="utf-8")
    source = handler + f"approved_enrolment = {rows!r}\n\n" + batch
    compile(source, str(target), "exec")
    with target.open("x", encoding="utf-8") as output:
        output.write(source)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", required=True, help="check every approved row using GET only")
    parser.add_argument("--candidates", type=Path, required=True, help="approved JSON with pos, dn and modified for each row")
    parser.add_argument("--render-console", type=Path, help="write a new local console file when all rows qualify")
    parser.add_argument("--url", default=os.getenv("POS_DELIVERY_ERP_URL"), required=not os.getenv("POS_DELIVERY_ERP_URL"))
    parser.add_argument("--key-path", default=os.getenv("POS_DELIVERY_ERP_KEY_PATH"), required=not os.getenv("POS_DELIVERY_ERP_KEY_PATH"))
    args = parser.parse_args()

    try:
        rows = read_candidates(args.candidates)
        api = Api(args.url, args.key_path)
        api.preflight()
        reviews = 0
        for row in rows:
            issue = review(api, row)
            if issue:
                print(api.redact(f"Review {row['pos']} / {row['dn']}: {issue}")[0])
                reviews += 1
            else:
                print(api.redact(f"Would enrol {row['pos']} / {row['dn']} (POS revision {row['modified']})")[0])
        print(f"{len(rows) - reviews} eligible. {reviews} need review. Dry run used GET only.")
        if reviews:
            return 1
        if args.render_console and rows:
            render_console(api, rows, args.render_console)
            print("Saved the reviewed console batch to a new local file.")
    except RolloutError as error:
        print(error, file=sys.stderr)
        return 1
    except (OSError, KeyError, ValueError, SyntaxError) as error:
        print(f"Enrolment stopped while reading or rendering the batch ({type(error).__name__}).", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
