# Ditto for Windows

A standalone, **local-only** Windows port of Ditto — the colorful snippet/clipboard
manager. This is a from-scratch rewrite (no Swift is shared) that aims for feature
parity with the macOS app, minus CloudKit sync.

## Stack

- **.NET 8 + WPF** for the UI (`net8.0-windows`)
- **EF Core 8 + SQLite** for storage — the local analogue of SwiftData
- **WinForms `NotifyIcon`** for the system tray (the analogue of `MenuBarExtra`)
- No third-party UI packages; icons use the built-in **Segoe MDL2 Assets** font

Database lives at `%APPDATA%\Ditto\ditto.db`; preferences at
`%APPDATA%\Ditto\settings.json`.

## Building (must be on Windows)

WPF only compiles on Windows, so build there:

```powershell
cd "Ditto Windows"
dotnet build                # debug build
dotnet run                  # build + launch
dotnet publish -c Release -r win-x64 --self-contained false   # shippable build
```

Requires the **.NET 8 SDK**. Visual Studio 2022 or `dotnet` CLI both work.

## Feature parity with the macOS app

Implemented:

- Category sidebar with **All Snippets**, **Frequent**, and per-category rows + counts
- Colored snippet **cards**: click to copy with a "Copied!" flash, hover styling
- Card **context menu**: Copy, Edit, Duplicate, Copy Share Link, Pin/Unpin, Open Link, Delete
- **Drag** a card to reorder within its group; **drop onto a sidebar category** to refile
  (or onto *All Snippets* to uncategorize)
- **Grouping** (None / Category / Date Added) with collapsible sections
- **5 zoom levels** for card size
- **Search** (title + content)
- **Snippet editor** (content / name / category) and **category editor**
  (name + 12-color palette + icon picker)
- **Tray dropdown** quick-copy popup: search, Frequently Used, per-category groups
- **JSON import/export** — byte-compatible with the Apple apps' `DittoExport` format
  (same keys, ISO-8601 dates), so a library exported on macOS imports here and back
- **`ditto://` URL scheme** (`add` + `import`) registered per-user; single-instance
  forwarding so a link activates the running app
- **Share links** (`ditto://import?data=…`, URL-safe base64) from cards and categories
- **Settings**: launch-at-login (registry Run key) and shared-link category behavior
- **Pinning** (pinned float to top), seed data on first run, menu bar (File/View/Help)

### Mapping notes

- **SF Symbols → Segoe MDL2 Assets.** The stored `symbolName` keeps the original SF
  identifier (e.g. `tag.fill`) so exports round-trip with the Apple apps; it is mapped
  to a Windows glyph only at display time (`Models/SymbolMap.cs`). A handful of glyphs
  are approximations — tweak the map freely.
- **Colors** approximate Apple's system palette by hex (`Models/ColorMap.cs`).
- **Login item** uses the per-user `Run` registry key instead of `SMAppService`.

## Known simplifications (vs. the macOS app)

These are deliberate scope cuts that a Windows pass can refine:

- Card reordering commits on drop without the macOS live "slide under the cursor"
  animation. Cross-category reordering is done via the sidebar, not by dragging
  between groups.
- Help/About are simple dialogs rather than dedicated windows.
- The card grid uses a fixed-width `WrapPanel` rather than a width-adaptive grid.

## Status

Written on macOS, so it has **not been compiled or run** — WPF needs Windows. Expect to
fix a few small things on first build (EF's navigation-setter fixup and exact Segoe
glyph choices are the most likely spots). The architecture and logic mirror the Swift
app closely, so issues should be localized.
