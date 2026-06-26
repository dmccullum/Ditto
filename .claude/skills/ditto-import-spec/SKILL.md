---
name: ditto-import-spec
description: >-
  Generate import content for the Ditto snippet manager — `ditto://add` links,
  `ditto://import` links (base64url-encoded JSON bundles), or the raw
  DittoExport `.json` file. Use this whenever the user wants to get snippets or
  categories INTO Ditto: turning a list of text (hashtags, links, bios, canned
  replies, templates, FAQ answers) into importable snippets, building a shareable
  Ditto link, seeding a category, or producing a Ditto backup/export file. Also
  use it to read or validate an existing `ditto://` link. Reach for this even
  when the user doesn't say "Ditto import" by name — e.g. "make a Ditto link for
  these", "add these snippets to Ditto", "bundle these as a category".
---

# Ditto import spec

Ditto is a snippet/clipboard manager (macOS + iOS). It ingests content through
the `ditto://` URL scheme, or by opening a `DittoExport` JSON file (File →
Import). This skill builds and validates that content.

## Pick the right form

- **One snippet, human-readable URL** → `ditto://add` (query parameters). Good
  for a quick single link someone can read.
- **Many snippets and/or whole categories** → `ditto://import?data=<base64url>`
  or a `.json` file. Both carry the same `DittoExport` bundle (full category
  styling, pins, dates). Use the link to paste somewhere; use the file for a
  backup or large library.

Generating an `import` link means base64url-encoding JSON exactly right. Don't
hand-roll it — use the bundled script (below), which also fills in the
boilerplate fields (`version`, `sortIndex`, `createdAt`, etc.) and prints both
the `.json` and the link.

## The script

`scripts/ditto_link.py` (stdlib only, Python 3) takes a small, friendly spec and
emits the canonical bundle and links.

```bash
# Build a DittoExport bundle + a ditto://import link from a simple spec file
python3 scripts/ditto_link.py bundle spec.json
python3 scripts/ditto_link.py bundle spec.json --out library.json   # also write the .json

# Build a single ditto://add link
python3 scripts/ditto_link.py add --content "Hello world" --title "Greeting" --category "Intros"

# Decode/inspect an existing link (add or import) back into readable JSON
python3 scripts/ditto_link.py decode "ditto://import?data=eyJ2ZXJ..."
```

The `bundle` input spec is the easy shape — the script expands it to the full
`DittoExport`:

```json
{
  "categories": [
    { "name": "Links", "symbolName": "link", "colorName": "blue" }
  ],
  "snippets": [
    { "title": "Site", "content": "https://example.com", "category": "Links", "isPinned": false }
  ]
}
```

- `category` on a snippet refers to a category `name`; omit it for uncategorized.
- A snippet's `category` that isn't in `categories` is allowed — on import Ditto
  creates it with default styling, but prefer declaring it so you control the
  icon/color.
- Order in the arrays becomes `sortIndex`. The script stamps `createdAt`/
  `exportedAt` with the current time unless you supply them.

## When hand-writing JSON or links

If you must write the bundle yourself (no Python available), follow
`references/json-format.md` exactly — it has the full schema, the encoding rules
for the `import` link, and the valid color/icon values. The two most common
mistakes are: using standard base64 instead of **URL-safe, unpadded** base64,
and using a `colorName` outside the palette (it silently falls back to blue).

## Validate before handing it back

A `ditto://import` link is opaque once encoded, so round-trip it to be sure:
run `decode` on what you produced and confirm the JSON matches the user's
intent. For `ditto://add`, check that `content` is present and everything is
percent-encoded.

## Import behavior the user should know

- **Categories merge by name, case-insensitively.** An existing category keeps
  its own icon/color — an import never overwrites the user's styling. Only new
  names are created.
- **Snippets dedupe** on (category + title + content), so re-importing the same
  bundle is idempotent — no duplicates.
- New items append after the current highest `sortIndex`.
- A user setting can force imported snippets to land uncategorized (ignoring the
  bundle's categories). Don't rely on category placement as guaranteed.
