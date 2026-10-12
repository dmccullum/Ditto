# Ditto

A colorful snippet manager for text you paste over and over: hashtags, links, bios, canned replies, templates. Click a snippet to copy it.

Ditto lives in two places:

| Platform | Folder | Stack |
|---|---|---|
| macOS (menu bar app) | [`Ditto/`](Ditto) | SwiftUI, SwiftData |
| iOS | [`Ditto iOS/`](Ditto%20iOS) | SwiftUI, SwiftData, App Intents |

## Building

Requires Xcode with the macOS 26 and iOS 26 SDKs.

```bash
open Ditto.xcodeproj
```

Choose the `Ditto` scheme for the Mac app or the iOS scheme for iPhone, then set your own signing team under *Signing & Capabilities* (the project currently references the author's team and bundle IDs, `com.danielmccullum.ditto*`, so you'll need to change those to run on a device).

To build and install the Mac app to `/Applications` in one step, run `Build Ditto.command`.

## Import links

Ditto registers a `ditto://` URL scheme so snippets and whole categories can be shared as links. See [`docs/ditto-link-prompt.md`](docs/ditto-link-prompt.md) for a prompt that makes any LLM generate them, and [`.claude/skills/ditto-import-spec`](.claude/skills/ditto-import-spec) for the format.

## License

[GPL-3.0](LICENSE)
