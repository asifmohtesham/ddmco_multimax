#!/usr/bin/env python3
"""Snapshot live POS Upload delivery readiness with GETs only."""

import argparse
import json
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path

from apply import LIVE, SERVER_SCRIPTS_ENABLED, RolloutError
from capture_live import ReadOnlyLive


STATUSES = ("Pending", "In Progress", "Completed", "Cancelled")
OPEN_STATUSES = (None, "", "Pending", "In Progress")
DISPATCHER_ROLES = {"Stock Manager", "Stock User", "Delivery Manager", "Delivery User"}
POS_FIELDS = ["name", "status", "docstatus", "modified", "customer"]
NOTE_FIELDS = [
    "name", "po_no", "docstatus", "company", "customer", "total_qty",
    "modified", "posting_date", "posting_time",
]


def list_linked(api, field, names, filters, fields):
    names = sorted(set(names))
    for start in range(0, len(names), 30):
        batch = names[start:start + 30]
        yield from api.list("Delivery Note", {**filters, field: ["in", batch]}, fields)


def note_mismatches(note, pos):
    reasons = []
    if note["company"] != "Multimax":
        reasons.append("company differs from Multimax")
    if note["customer"] != pos["customer"]:
        reasons.append("customer differs from POS")
    if Decimal(str(note["total_qty"] or 0)) <= 0:
        reasons.append("quantity is not positive")
    return reasons


def submit_version(api, note_name):
    versions = api.list("Version", {"ref_doctype": "Delivery Note", "docname": note_name},
                        ["name", "creation", "data"])
    for version in sorted(versions, key=lambda row: (row["creation"], row["name"]), reverse=True):
        changes = json.loads(version["data"] or "{}").get("changed") or []
        if any(len(change) == 3 and change[0] == "docstatus"
               and str(change[1]) == "0" and str(change[2]) == "1" for change in changes):
            return version["name"], version["creation"]
    return None, None


def review_open_pos(api, open_rows):
    notes_by_pos = defaultdict(list)
    pos_names = {row["name"] for row in open_rows}
    normalized_names = defaultdict(list)
    for name in pos_names:
        normalized_names[name.strip().casefold()].append(name)
    nonexact_by_pos = defaultdict(list)
    for note in list_linked(api, "po_no", pos_names,
                            {"docstatus": ["in", [0, 1]], "is_return": 0}, NOTE_FIELDS):
        if note["po_no"] in pos_names:
            notes_by_pos[note["po_no"]].append(note)
            continue
        for name in normalized_names[(note["po_no"] or "").strip().casefold()]:
            nonexact_by_pos[name].append(note["name"])

    submitted_names = [note["name"] for notes in notes_by_pos.values()
                       for note in notes if note["docstatus"] == 1]
    returns_by_dn = defaultdict(list)
    for row in list_linked(api, "return_against", submitted_names,
                           {"docstatus": 1, "is_return": 1}, ["name", "return_against"]):
        returns_by_dn[row["return_against"]].append(row["name"])

    candidates, reviews = [], []
    for pos in open_rows:
        name = pos["name"]
        notes = notes_by_pos[name]
        submitted = [note for note in notes if note["docstatus"] == 1]
        drafts = [{**note, "mismatches": note_mismatches(note, pos)}
                  for note in notes if note["docstatus"] == 0]
        issues = []
        if len(submitted) != 1:
            issues.append(f"{len(submitted)} exact-PO submitted outbound Delivery Notes")
        if nonexact_by_pos[name]:
            issues.append("Nonexact PO references: " + ", ".join(nonexact_by_pos[name]))
        if not name.startswith(("ML-", "KA-")) or pos["docstatus"] != 0:
            issues.append("POS is outside the draft ML-/KA- DN submit path")
        for note in submitted:
            mismatches = note_mismatches(note, pos)
            returns = returns_by_dn[note["name"]]
            if returns:
                mismatches.append("submitted stock returns: " + ", ".join(returns))
            if mismatches:
                issues.append(note["name"] + ": " + ", ".join(mismatches))

        row = {"pos": name, "status": pos["status"], "modified": pos["modified"], "drafts": drafts}
        if issues:
            reviews.append({**row, "submitted_outbound_dns": [note["name"] for note in submitted],
                            "issues": issues})
            continue
        note = submitted[0]
        version, submitted_at = submit_version(api, note["name"])
        candidates.append({**row, "dn": note["name"], "dn_modified": note["modified"],
                           "submission_version": version, "submitted_at": submitted_at,
                           "posting_date": note["posting_date"], "posting_time": note["posting_time"]})
    return candidates, reviews


def get_dispatchers(api):
    rows = api.list("User", {"enabled": 1, "user_type": "System User"})
    dispatchers = []
    for row in rows:
        user = api.get("User", row["name"])
        if not user or not user["enabled"] or user["user_type"] != "System User":
            raise RolloutError("A User changed during the scan. Refresh the readiness snapshot.")
        roles = sorted({assignment["role"] for assignment in user.get("roles", [])})
        if DISPATCHER_ROLES.intersection(roles):
            dispatchers.append({"name": user["name"], "full_name": user["full_name"], "roles": roles})
    return len(rows), dispatchers


def scan(api):
    started = datetime.now(timezone.utc).isoformat()
    enabled = api.request("GET", SERVER_SCRIPTS_ENABLED).get("message") is True
    pos_rows = api.list("POS Upload", {}, POS_FIELDS)
    if len({row["name"] for row in pos_rows}) != len(pos_rows):
        raise RolloutError("POS pagination returned duplicates. Refresh the readiness snapshot.")

    status_counts = Counter(row["status"] for row in pos_rows if row["status"] not in (None, ""))
    other_counts = {status: count for status, count in status_counts.items() if status not in STATUSES}
    blanks, historical = [], []
    for row in pos_rows:
        revision = {field: row[field] for field in ("name", "status", "docstatus", "modified")}
        if row["status"] in (None, ""):
            blanks.append(revision)
        elif row["status"] in ("Completed", "Cancelled"):
            historical.append(revision)

    open_rows = [row for row in pos_rows if row["status"] in OPEN_STATUSES]
    candidates, reviews = review_open_pos(api, open_rows)
    drivers = api.list("Driver", {"status": "Active"}, ["name", "full_name"])
    drivers.sort(key=lambda row: ((row["full_name"] or "").casefold(), row["name"]))
    user_count, dispatchers = get_dispatchers(api)
    report = {
        "scan_started_utc": started,
        "scan_finished_utc": datetime.now(timezone.utc).isoformat(),
        "server_scripts_enabled": enabled,
        "pos_total": len(pos_rows),
        "status_counts": {"Blank": len(blanks), **{status: status_counts[status] for status in STATUSES},
                          "Other": sum(other_counts.values())},
        "other_status_counts": other_counts,
        "blank_draft_count": sum(row["docstatus"] == 0 for row in blanks),
        "open_count": len(open_rows),
        "candidates": candidates,
        "reviews": reviews,
        "drivers": drivers,
        "enabled_system_users": user_count,
        "dispatchers": dispatchers,
    }
    return report, blanks, historical


def write_snapshot(api, output_dir):
    report, blanks, historical = scan(api)
    for filename, contents in (("readiness-data.json", report), ("readiness-blanks.json", blanks),
                               ("readiness-history.json", historical)):
        with (output_dir / filename).open("x", encoding="utf-8", newline="\n") as handle:
            json.dump(api.redact(contents)[0], handle, ensure_ascii=False, indent=2)
            handle.write("\n")
    print(f"{report['pos_total']} POS Uploads, {report['blank_draft_count']} draft blanks, "
          f"{len(report['candidates'])} enrolment candidates, {len(report['reviews'])} open reviews, "
          f"{len(report['drivers'])} active Drivers, {len(report['dispatchers'])} dispatcher candidates.")
    if not report["server_scripts_enabled"]:
        raise RolloutError("Server Scripts are disabled. Stop before applying.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key-path", required=True)
    parser.add_argument("--output-dir", type=Path, required=True, help="fresh local scratch directory")
    args = parser.parse_args()
    try:
        args.output_dir.mkdir(parents=True)
        write_snapshot(ReadOnlyLive(LIVE, args.key_path), args.output_dir)
    except (OSError, RolloutError, KeyError, TypeError, ValueError, ArithmeticError) as error:
        print(error if isinstance(error, RolloutError) else
              f"Live readiness scan stopped ({type(error).__name__}).", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
