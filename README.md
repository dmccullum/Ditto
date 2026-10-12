# Ditto

A colorful snippet manager for text you paste over and over: hashtags, links, bios, canned replies, templates. Click a snippet to copy it.

Ditto lives in two places:

| Platform | Folder | Stack |
|---|---|---|
| macOS (menu bar app) | [`Ditto/`](Ditto) | SwiftUI, SwiftData |
| iOS | [`Ditto iOS/`](Ditto%20iOS) | SwiftUI, SwiftData, App Intents |

## Building

Requires macOS 26 and Xcode 26.

**Mac app, no Apple account needed:** double-click `Build Ditto.command` (or run it from a terminal). It builds an ad-hoc signed Release build, installs it to `/Applications`, and launches it.

**In Xcode:** `open Ditto.xcodeproj`, pick the `Ditto` (Mac) or iOS scheme, and choose your own team under *Signing & Capabilities*. The simulator works without a team. To run the iOS app on a real device, also change the bundle ID (`com.danielmccullum.ditto.ios`) to one of your own.

## Import links

Ditto registers a `ditto://` URL scheme so snippets and whole categories can be shared as links. See [`docs/ditto-link-prompt.md`](docs/ditto-link-prompt.md) for a prompt that makes any LLM generate them, and [`.claude/skills/ditto-import-spec`](.claude/skills/ditto-import-spec) for the format.

## License

[GPL-3.0](LICENSE)
