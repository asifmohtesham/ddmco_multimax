#!/usr/bin/env python3
"""Save POS Upload delivery before-images from live using GETs only."""

import argparse
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

from apply import (
    LIVE,
    PERMISSIONS,
    SCOPES,
    Api,
    RolloutError,
    doc_key,
    load_records,
    save_before_images,
)


class ReadOnlyLive(Api):
    def request(self, method, path, payload=None, query=None):
        if method != "GET" or payload is not None:
            raise RolloutError("Live capture accepts GETs without a request body only.")
        return super().request(method, path, query=query)

    def redact(self, value):
        if isinstance(value, dict) and value.get("doctype") == "Webhook":
            safe, paths = super().redact(value)
            for idx, header in enumerate(safe.get("webhook_headers", [])):
                if header.get("value") and header.get("key", "").lower() not in {"accept", "content-type"}:
                    header["value"] = "[REDACTED]"
                    paths.append(f"webhook_headers[{idx}].value")
            url = value.get("request_url")
            if url:
                # Redact dynamic URLs in full, plus opaque path segments and all URL query values.
                parts = urlsplit(url)
                if value.get("is_dynamic_url") or not parts.hostname:
                    safe_url = "[REDACTED]"
                else:
                    path = re.sub(r"(?<=/)[^/]+", self.safe_segment, parts.path)
                    host = parts.netloc.rsplit("@", 1)[-1]
                    netloc = "[REDACTED]@" + host if "@" in parts.netloc else host
                    safe_url = urlunsplit((parts.scheme, netloc, path,
                                           "[REDACTED]" if parts.query else "",
                                           "[REDACTED]" if parts.fragment else ""))
                if safe_url != url:
                    safe["request_url"] = super().redact(safe_url)[0]
                    paths.append("request_url")
            return safe, sorted(set(paths))
        return super().redact(value)

    @staticmethod
    def safe_segment(match):
        segment = match.group()
        if segment in {"webhook", "webhook-test", "pos-upload-delivery"}:
            return segment
        return "[REDACTED]"


def capture_live(api, before_dir):
    if (before_dir / "manifest.json").exists():
        raise RolloutError("Before-images already exist. Use a fresh directory.")

    targets = {
        doc_key(record) for record in load_records() if record["doctype"] != "Custom DocPerm"
    }
    listed = set()
    for doctype, filters in (*SCOPES, ("Webhook", {"webhook_doctype": "POS Upload"})):
        listed.update((doctype, row["name"]) for row in api.list(doctype, filters))

    docs = {}
    for doctype, name in sorted(targets | listed):
        doc = api.get(doctype, name)
        if doc is None:
            if (doctype, name) in listed:
                raise RolloutError(f"A listed {doctype} disappeared during capture. Use a fresh directory and repeat.")
            continue
        docs[doc_key(doc)] = doc

    baseline = {
        parent: api.redact(api.request("GET", PERMISSIONS + "get_standard_permissions",
                                      query={"doctype": parent})["message"])[0]
        for parent in ("POS Upload", "Driver")
    }
    save_before_images(api, docs, baseline, before_dir)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key-path", required=True)
    parser.add_argument("--before-dir", type=Path, required=True)
    args = parser.parse_args()
    try:
        capture_live(ReadOnlyLive(LIVE, args.key_path), args.before_dir)
    except (RolloutError, OSError, KeyError, ValueError) as error:
        print(error if isinstance(error, RolloutError) else
              f"Live capture stopped ({type(error).__name__}).", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
