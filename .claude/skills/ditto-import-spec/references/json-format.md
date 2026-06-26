# Ditto import format — full reference

Source of truth: `Ditto/Support/ImportExport.swift`, `Ditto/Support/SnippetURL.swift`,
`Ditto/Support/SnippetColor.swift` (mirrored in `Ditto iOS/Support/`).

## Contents
- [URL form 1: ditto://add](#url-form-1-dittoadd)
- [URL form 2: ditto://import](#url-form-2-dittoimport)
- [The DittoExport JSON bundle](#the-dittoexport-json-bundle)
- [base64url encoding for the import link](#base64url-encoding-for-the-import-link)
- [Valid colorName values](#valid-colorname-values)
- [Valid symbolName values](#valid-symbolname-values)
- [Import/merge behavior](#importmerge-behavior)

## URL form 1: ditto://add

A single snippet as readable query parameters:

```
ditto://add?content=<text>&title=<name>&category=<name>
```

- `content` — **required**; the snippet body. Empty/whitespace-only → the link is ignored.
- `title` — optional display name.
- `category` — optional; matched case-insensitively to an existing category, or
  created with default styling (`tag.fill`, blue) if new.

All values must be percent-encoded (`Hello world` → `Hello%20world`). Newlines in
`content` are fine when encoded (`%0A`).

## URL form 2: ditto://import

```
ditto://import?data=<base64url-encoded DittoExport JSON>
```

The `data` value is the JSON below, UTF-8, then base64url-encoded (see
[encoding](#base64url-encoding-for-the-import-link)). Carries many snippets and
full category definitions in one link. This is also exactly what File → Export
writes (as a plain `.json` file) and what the in-app Share Link / Copy Share
Link actions produce.

## The DittoExport JSON bundle

```json
{
  "version": 1,
  "exportedAt": "2026-06-26T14:30:00Z",
  "categories": [
    {
      "name": "Hashtags",
      "symbolName": "number",
      "colorName": "pink",
      "sortIndex": 0
    }
  ],
  "snippets": [
    {
      "title": "Daily content tags",
      "content": "#contentcreator #socialmedia #marketing",
      "categoryName": "Hashtags",
      "isPinned": false,
      "sortIndex": 0,
      "createdAt": "2026-06-01T09:00:00Z"
    }
  ]
}
```

### Top level
| Field | Type | Required | Notes |
|---|---|---|---|
| `version` | Int | yes | Currently `1`. |
| `exportedAt` | ISO 8601 date | yes | Informational. |
| `categories` | array | yes | May be empty (`[]`). |
| `snippets` | array | yes | May be empty (`[]`). |

### categories[]
| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | String | yes | Display name; snippets reference it via `categoryName`. |
| `symbolName` | String | yes | SF Symbol name — see [valid values](#valid-symbolname-values). |
| `colorName` | String | yes | Palette name — see [valid values](#valid-colorname-values). |
| `sortIndex` | Int | yes | Order among categories (ascending). |

### snippets[]
| Field | Type | Required | Notes |
|---|---|---|---|
| `title` | String | yes | May be `""`; the app then shows the first content line. |
| `content` | String | yes | The actual snippet text. |
| `categoryName` | String or null | yes | Name of a category, or `null` for uncategorized. |
| `isPinned` | Bool | yes | |
| `sortIndex` | Int | yes | Order (ascending). |
| `createdAt` | ISO 8601 date | yes | Preserved on import (not reset to "now"). |

Encoder notes (match File → Export output): keys are sorted, dates are ISO 8601.
Pretty-printing is optional — whitespace doesn't matter to the importer.

## base64url encoding for the import link

The `import` link uses **URL-safe, unpadded** base64 (RFC 4648 §5), NOT standard
base64. Steps:

1. Serialize the bundle to UTF-8 JSON bytes.
2. Standard base64-encode.
3. Replace `+` → `-` and `/` → `_`.
4. Strip all `=` padding.
5. `ditto://import?data=<result>`

The decoder reverses this and re-pads, so producing a correct link means getting
exactly steps 3–4 right. (Standard base64 with `+`/`/`/`=` will break in a URL.)

## Valid colorName values

22 names. Anything else falls back to **blue** on display, so stick to these:

```
red, coral, orange, gold, yellow, lime, green, forest, mint, teal, cyan,
sky, blue, navy, indigo, lavender, purple, plum, pink, rose, brown, slate
```

(The 12 system colors — red, orange, yellow, green, mint, teal, cyan, blue,
indigo, purple, pink, brown — adapt to light/dark mode; the other 10 are fixed
mid-tones.)

## Valid symbolName values

`symbolName` is rendered with SwiftUI `Image(systemName:)`, so technically any
valid SF Symbol works. To match the in-app picker (and be sure it renders),
prefer this curated set:

**Text & writing:** `textformat` `paragraph` `square.and.pencil` `note.text`
`text.alignleft` `text.cursor` `signature` `character`
**Code & technical:** `curlybraces` `terminal.fill` `function` `command`
`keyboard` `gearshape.fill` `cpu` `qrcode` `ladybug.fill`
**Security:** `lock.fill` `key.fill` `shield.fill`
**Lists & structure:** `list.bullet` `list.number` `checklist` `list.clipboard`
**Documents:** `doc.text.fill` `text.quote` `number` `paperclip`
**Links & social:** `link` `at` `bubble.left.fill` `megaphone.fill`
`envelope.fill` `phone.fill` `paperplane.fill` `bell.fill` `wifi`
**Creative & media:** `wand.and.stars` `sparkles` `arrow.triangle.2.circlepath`
`paintpalette.fill` `camera.fill` `music.note` `photo.fill` `film.fill`
`tv.fill` `headphones` `mic.fill` `guitars.fill` `theatermasks.fill`
**Organisation:** `tag.fill` `bookmark.fill` `star.fill` `heart.fill`
`bolt.fill` `flame.fill` `calendar` `clock`
**Work & money:** `briefcase.fill` `building.2.fill` `chart.bar.fill`
`chart.line.uptrend.xyaxis` `dollarsign.circle.fill` `creditcard.fill`
`cart.fill` `shippingbox.fill`
**Home & life:** `house.fill` `car.fill` `fork.knife` `cup.and.saucer.fill`
`cross.case.fill` `pills.fill` `dumbbell.fill` `lightbulb.fill` `hammer.fill`
`scissors` `umbrella.fill` `leaf.fill`
**Travel & places:** `airplane` `map.fill` `suitcase.fill` `tent.fill`
`sailboat.fill` `globe`
**Learning:** `graduationcap.fill` `book.fill` `brain.head.profile` `atom`
**People:** `person.fill` `person.2.fill`
**Games & celebration:** `gamecontroller.fill` `dice.fill` `puzzlepiece.fill`
`face.smiling.fill` `party.popper.fill` `balloon.2.fill` `gift.fill`
`crown.fill` `trophy.fill` `birthday.cake.fill`
**Nature & critters:** `sun.max.fill` `moon.stars.fill` `snowflake` `rainbow`
`fireworks` `pawprint.fill` `cat.fill` `dog.fill` `bird.fill` `fish.fill`
`hare.fill` `tortoise.fill` `teddybear.fill`

Default when unsure: `tag.fill`.

## Import/merge behavior

- **Categories merge by name (case-insensitive).** An existing category keeps
  its own `symbolName`/`colorName` — import never clobbers the user's styling.
  Only genuinely new names are created.
- **Snippets dedupe** on the tuple (lowercased categoryName, title, content), so
  re-importing the same bundle adds nothing — it's idempotent.
- New items are appended after the current highest `sortIndex`.
- A user preference ("import as uncategorized") can drop the bundle's categories
  entirely, filing every snippet as uncategorized. Don't depend on category
  placement being honored.
- `ditto://add` finds the next `sortIndex` by max-of-existing + 1.
