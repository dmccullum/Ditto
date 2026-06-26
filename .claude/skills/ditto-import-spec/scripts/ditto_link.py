#!/usr/bin/env python3
"""Build and decode Ditto import content.

Mirrors Ditto/Support/ImportExport.swift and SnippetURL.swift:
- DittoExport JSON bundle (version 1, ISO 8601 dates, sorted keys)
- ditto://import?data=<URL-safe, unpadded base64 of the bundle>
- ditto://add?content=...&title=...&category=...

Stdlib only. Python 3.8+.

Subcommands:
  bundle <spec.json> [--out FILE]   Expand a simple spec into a DittoExport
                                    bundle + a ditto://import link.
  add --content T [--title T] [--category T]
                                    Build a single ditto://add link.
  decode <url|data>                 Decode a ditto:// link (or raw data=) back
                                    into readable JSON.

The `bundle` spec is the friendly shape:
  {
    "categories": [ {"name": "Links", "symbolName": "link", "colorName": "blue"} ],
    "snippets":   [ {"title": "Site", "content": "https://x.com",
                     "category": "Links", "isPinned": false} ]
  }
Order becomes sortIndex; createdAt/exportedAt default to now (UTC).
"""

import argparse
import base64
import json
import sys
from datetime import datetime, timezone
from urllib.parse import urlsplit, parse_qs, quote

VALID_COLORS = {
    "red", "coral", "orange", "gold", "yellow", "lime", "green", "forest",
    "mint", "teal", "cyan", "sky", "blue", "navy", "indigo", "lavender",
    "purple", "plum", "pink", "rose", "brown", "slate",
}


def _now_iso() -> str:
    # e.g. 2026-06-26T14:30:00Z  (matches the app's ISO 8601 encoding)
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def b64url_encode(raw: bytes) -> str:
    """URL-safe base64, padding stripped (RFC 4648 §5) — what the link uses."""
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def b64url_decode(s: str) -> bytes:
    """Reverse b64url_encode, re-padding as the app's decoder does."""
    s = s.replace("-", "+").replace("_", "/")
    pad = (-len(s)) % 4
    return base64.b64decode(s + "=" * pad)


def build_bundle(spec: dict) -> dict:
    """Expand the friendly spec into a full DittoExport bundle."""
    warnings = []
    categories = []
    for i, c in enumerate(spec.get("categories", [])):
        name = c.get("name", "").strip()
        if not name:
            warnings.append(f"category #{i} has no name; skipped")
            continue
        color = c.get("colorName", "blue")
        if color not in VALID_COLORS:
            warnings.append(f"category '{name}': colorName '{color}' is not in the "
                            f"palette and will show as blue")
        categories.append({
            "name": name,
            "symbolName": c.get("symbolName", "tag.fill"),
            "colorName": color,
            "sortIndex": c.get("sortIndex", i),
        })

    snippets = []
    for i, s in enumerate(spec.get("snippets", [])):
        content = s.get("content", "")
        if not content.strip():
            warnings.append(f"snippet #{i} has empty content; skipped")
            continue
        # Accept either "category" (friendly) or "categoryName" (canonical).
        cat = s.get("categoryName", s.get("category"))
        snippets.append({
            "title": s.get("title", ""),
            "content": content,
            "categoryName": cat if cat else None,
            "isPinned": bool(s.get("isPinned", False)),
            "sortIndex": s.get("sortIndex", i),
            "createdAt": s.get("createdAt", _now_iso()),
        })

    bundle = {
        "version": 1,
        "exportedAt": spec.get("exportedAt", _now_iso()),
        "categories": categories,
        "snippets": snippets,
    }
    return bundle, warnings


def bundle_json(bundle: dict) -> str:
    # sort_keys mirrors the app's .sortedKeys output.
    return json.dumps(bundle, sort_keys=True, indent=2, ensure_ascii=False)


def import_link(bundle: dict) -> str:
    raw = json.dumps(bundle, sort_keys=True, separators=(",", ":"),
                     ensure_ascii=False).encode("utf-8")
    return "ditto://import?data=" + b64url_encode(raw)


def cmd_bundle(args):
    with open(args.spec, "r", encoding="utf-8") as f:
        spec = json.load(f)
    bundle, warnings = build_bundle(spec)
    for w in warnings:
        print(f"warning: {w}", file=sys.stderr)
    js = bundle_json(bundle)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(js + "\n")
        print(f"wrote {args.out}", file=sys.stderr)
    print("=== DittoExport JSON ===")
    print(js)
    print("\n=== ditto://import link ===")
    print(import_link(bundle))


def cmd_add(args):
    if not args.content.strip():
        sys.exit("error: --content is required and must be non-empty")
    parts = [f"content={quote(args.content)}"]
    if args.title:
        parts.append(f"title={quote(args.title)}")
    if args.category:
        parts.append(f"category={quote(args.category)}")
    print("ditto://add?" + "&".join(parts))


def cmd_decode(args):
    arg = args.url
    data = None
    if arg.startswith("ditto://"):
        parts = urlsplit(arg)
        # urlsplit treats the host as the action (add/import).
        action = parts.netloc or parts.path.lstrip("/")
        qs = parse_qs(parts.query)
        if action == "import":
            data = qs.get("data", [None])[0]
            if not data:
                sys.exit("error: import link has no data= parameter")
            raw = b64url_decode(data)
            print(json.dumps(json.loads(raw), sort_keys=True, indent=2, ensure_ascii=False))
            return
        elif action == "add":
            decoded = {k: v[0] for k, v in qs.items()}
            print(json.dumps(decoded, sort_keys=True, indent=2, ensure_ascii=False))
            return
        else:
            sys.exit(f"error: unknown ditto action '{action}'")
    # Otherwise treat the argument as a raw data= payload.
    raw = b64url_decode(arg)
    print(json.dumps(json.loads(raw), sort_keys=True, indent=2, ensure_ascii=False))


def main():
    p = argparse.ArgumentParser(description="Build/decode Ditto import content.")
    sub = p.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("bundle", help="Expand a spec into a DittoExport + import link")
    b.add_argument("spec", help="Path to the friendly spec JSON")
    b.add_argument("--out", help="Also write the DittoExport JSON to this file")
    b.set_defaults(func=cmd_bundle)

    a = sub.add_parser("add", help="Build a single ditto://add link")
    a.add_argument("--content", required=True)
    a.add_argument("--title")
    a.add_argument("--category")
    a.set_defaults(func=cmd_add)

    d = sub.add_parser("decode", help="Decode a ditto:// link or raw data= payload")
    d.add_argument("url", help="A ditto://add / ditto://import link, or a data= payload")
    d.set_defaults(func=cmd_decode)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
