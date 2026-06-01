# Listing Studio Handoff

This document captures the product direction discussed for a new app idea that should be taken into a fresh session. It is intentionally separate from Ditto: the apps should feel like siblings visually, but they solve different jobs.

## Product Idea

**Working name:** Listing Studio

**Purpose:** A native macOS workflow tool for turning real estate listing inputs and listing photos into polished social media post assets.

The app should help a social media manager:

- Enter or paste listing details.
- Generate or paste platform-ready captions.
- Drop in a folder of property photos.
- Automatically identify the best photos.
- Crop selected photos artfully to a repeatable aspect ratio, especially 3:4.
- Apply native design templates with editable text overlays.
- Export final social slides/images.
- Maintain a project history so past listings can be reopened, reused, or re-exported.

## Relationship To Ditto

This should **not** be integrated into Ditto.

Ditto is a snippets utility for reusable text. Listing Studio is a one-off campaign/listing production tool. Captions and listing outputs are usually used once or twice, so they do not naturally belong in a snippets library.

That said, the two apps should feel like siblings:

- Same general Mac-ish visual tone.
- Similar colorful but restrained design language.
- Native SwiftUI architecture.
- Familiar sidebar/detail structure where useful.
- Similar app polish: custom About, Help, Settings, menu commands, keyboard shortcuts.

Optional future bridge:

- Listing Studio could offer "Save caption to Ditto" or emit a `ditto://add` link, but this should not be part of the core MVP.

## Key Decisions Already Made

- Build as a **separate native macOS app**, not a Ditto tab.
- Native SwiftUI templates are acceptable, probably preferred, because the designs are repeatable.
- The app needs **multiple layout choices**, not arbitrary freeform design editing.
- The app needs **project history**.
- AI caption generation is useful, but should not require an API for MVP.
- A paid Claude/OpenAI API key would be required for fully automated in-app generation. Claude Pro allowance cannot be used by a custom app.
- A practical MVP can use the user's existing Claude Pro workflow: generate captions in Claude, then paste them into Listing Studio.
- Image selection/cropping can be mostly on-device using Apple's Vision framework, with no paid AI API.

## Why Not Use Claude Pro Directly Inside The App?

Claude Pro and API usage are separate products.

A custom app cannot draw from a Claude Pro subscription allowance. To call Claude from an app, the user needs an Anthropic API key from `console.anthropic.com`, billed separately per token.

Suggested product path:

1. MVP: no API. User pastes captions generated in Claude/ChatGPT.
2. Later: optional "Bring your own API key" setting, stored in Keychain.
3. Much later, if distributed broadly: backend proxy for API keys/billing, but this adds infrastructure and security responsibility.

## Core Workflow

Suggested pipeline:

```text
Create project
→ enter listing details
→ generate/paste captions
→ drop photo folder
→ score/rank photos
→ auto-crop top candidates to 3:4
→ choose design layout
→ edit text overlays
→ preview slides
→ export PNG/JPEG assets
→ save project history
```

## MVP Scope

### Project History

The app should have a project library/history. Each project represents one listing or campaign.

Suggested fields:

- Project name
- Listing address
- Status: Draft / Ready / Exported / Archived
- Created date
- Updated date
- Exported date, optional
- Listing details
- Selected layout
- Selected/cropped photos
- Overlay text
- Captions
- Export settings

UI idea:

- Sidebar or project browser with recent projects.
- Detail view for the selected project.
- New Project button.
- Duplicate Project may be useful for recurring listing styles.

Storage:

- SwiftData is fine for metadata.
- Store original/imported images and rendered exports in the app's Application Support folder, referenced by file URL/path from SwiftData.
- Avoid storing huge image blobs directly in SwiftData.

### Listing Input

Fields could include:

- Property address
- City/neighborhood
- Price
- Beds
- Baths
- Square footage
- Lot size
- Listing agent/team
- Brokerage
- Key features
- Open house date/time
- MLS/listing URL
- Call to action

The input form should be ergonomic, not marketing-page-like. Think quiet, dense, useful.

### Captions

MVP:

- User pastes captions manually from Claude/ChatGPT.
- Keep variants per platform:
  - Instagram
  - Facebook
  - LinkedIn
  - X
- Live character counts.
- Optional hashtag field.
- Copy buttons.

Future API mode:

- Store API key in Keychain.
- Use `URLSession` for Anthropic/OpenAI requests.
- Ask the model for structured JSON, not prose.
- Generate platform-specific variants.
- Include tone controls and constraints.

### Image Import

MVP should allow:

- Drop a folder of images.
- Pick images via `NSOpenPanel`.
- Show a review grid with thumbnails.
- Rank/sort by quality.
- Let user select final images.

Supported formats:

- JPEG
- PNG
- HEIC, if convenient through `NSImage`/ImageIO

### On-device Photo Ranking

Use Apple's Vision framework before paying for cloud AI.

Useful APIs:

- `VNCalculateImageAestheticsScoresRequest`
  - Rank photos by `overallScore`.
  - Use `isUtility` to filter screenshots/documents/receipts.
- `VNGenerateImageFeaturePrintRequest`
  - Detect near-duplicate images.
  - Cluster similar shots and keep the best-scoring one.
- Optional sharpness check
  - Use Core Image or Accelerate/Laplacian variance if explicit blur detection is needed.

Selection approach:

1. Score all images.
2. Filter out low-quality/utility images.
3. Cluster near-duplicates.
4. Keep top-ranked image per cluster.
5. Present candidates with "AI picked" badges, but let user override.

### Artful 3:4 Auto-Cropping

Goal: choose crops that feel intentional, not naive center crops.

Use Vision:

- `VNGenerateAttentionBasedSaliencyImageRequest`
  - Find visually important regions.
- `VNDetectFaceRectanglesRequest`
  - Keep people/faces inside crop.
- `VNDetectHorizonRequest`
  - Straighten exteriors/landscapes and avoid awkward horizons.

Crop algorithm idea:

1. Define target aspect ratio, initially 3:4.
2. Generate candidate crop rectangles across the image.
3. Score candidates by saliency coverage.
4. Bias salient subject toward rule-of-thirds positions.
5. Penalize crops that cut off faces.
6. Optionally straighten horizon first.
7. Crop with `cgImage.cropping(to:)`.

UI:

- Show auto-crop preview.
- Allow manual pan/zoom nudge.
- Include presets:
  - 3:4 primary
  - 4:5 Instagram portrait
  - 1:1 square
  - 9:16 story/reel
  - 1.91:1 LinkedIn/Facebook landscape

### Native Design Templates

Decision: native templates are acceptable because the designs are repeatable.

Use SwiftUI views as templates:

- `ZStack` with image, gradients, text overlays, badges, logos.
- Render output with `ImageRenderer`.
- Export PNG/JPEG.

Why native templates:

- No PSD parsing.
- No Canva API requirement.
- Full control over text, gradients, shadows, badges.
- Easy to offer a curated set of layouts.
- WYSIWYG preview matches export.

Template model:

- Layout name
- Target aspect ratio / export size
- Image placement rules
- Text fields:
  - headline
  - subheadline
  - price
  - address
  - beds/baths/sqft
  - CTA
- Text style presets
- Color palette / gradient preset
- Optional logo/brokerage badge

Initial layout options:

1. **Hero Listing**
   - Full-bleed photo.
   - Gradient at bottom.
   - Address + price overlay.
2. **Open House**
   - Photo background.
   - Large date/time badge.
   - Address and CTA.
3. **Just Listed**
   - Photo with bold "Just Listed" label.
   - Property stats row.
4. **Feature Focus**
   - Photo plus short feature headline.
   - Good for kitchens, views, pools, etc.
5. **Clean Brokerage**
   - More restrained, premium feel.
   - Logo/name area.

Potential export code pattern:

```swift
struct SlideTemplateView: View {
    let image: NSImage
    let text: OverlayText
    let palette: TemplatePalette

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 1080, height: 1440)
                .clipped()

            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 12) {
                Text(text.headline)
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(.white)

                Text(text.subheadline)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .padding(56)
        }
        .frame(width: 1080, height: 1440)
    }
}
```

Render/export with:

```swift
@MainActor
func renderPNG<Content: View>(_ content: Content, to url: URL) throws {
    let renderer = ImageRenderer(content: content)
    renderer.scale = 1
    guard let cgImage = renderer.cgImage else { return }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try data.write(to: url, options: .atomic)
}
```

## Possible App Architecture

Native macOS SwiftUI app:

- SwiftUI
- SwiftData
- Vision
- Core Image / ImageIO
- AppKit for file pickers/export panels
- Keychain later if API key is added

Suggested file structure:

```text
ListingStudio/
  ListingStudioApp.swift
  Models/
    Project.swift
    ListingDetails.swift
    ListingPhoto.swift
    CropPreset.swift
    DesignTemplate.swift
    CaptionVariant.swift
  Views/
    ProjectBrowserView.swift
    ProjectDetailView.swift
    ListingFormView.swift
    CaptionEditorView.swift
    PhotoImportView.swift
    PhotoReviewGrid.swift
    CropEditorView.swift
    TemplatePickerView.swift
    ExportPreviewView.swift
  Services/
    PhotoImportService.swift
    VisionScoringService.swift
    SaliencyCropService.swift
    ExportRenderer.swift
    ProjectFileStore.swift
    LLMCaptionService.swift (future)
    KeychainStore.swift (future)
  Templates/
    HeroListingTemplate.swift
    OpenHouseTemplate.swift
    JustListedTemplate.swift
    FeatureFocusTemplate.swift
```

## Data Model Sketch

```swift
@Model
final class Project {
    var name: String = ""
    var statusRaw: String = "draft"
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var listing: ListingDetails?
    var selectedTemplateID: String = "hero"
    var captions: [CaptionVariant] = []
    var photos: [ListingPhoto] = []
}

@Model
final class ListingDetails {
    var address: String = ""
    var price: String = ""
    var beds: String = ""
    var baths: String = ""
    var squareFeet: String = ""
    var features: String = ""
    var callToAction: String = ""
}

@Model
final class ListingPhoto {
    var originalPath: String = ""
    var cropX: Double = 0
    var cropY: Double = 0
    var cropWidth: Double = 1
    var cropHeight: Double = 1
    var aestheticScore: Double = 0
    var isSelected: Bool = false
    var sortIndex: Int = 0
}
```

May need adjustment for SwiftData relationship constraints and CloudKit if sync is ever considered. For MVP, local-only is fine.

## Important UX Notes

- This should feel like a production workbench, not a marketing landing page.
- First screen should be the project browser or last project, not a hero page.
- The image review/crop workflow is central; it should be fast and visual.
- AI choices should be editable and overrideable.
- Project history is not optional; it is part of the app's usefulness.
- Exports should be deterministic and repeatable.
- Avoid turning it into Canva; offer curated templates, not a full design tool.

## MVP Build Order

Recommended order for a fresh session:

1. Scaffold standalone macOS SwiftUI app.
2. Add project history with SwiftData.
3. Add listing form.
4. Add manual caption fields and character counts.
5. Add folder/image import.
6. Add image grid and select/unselect.
7. Add a basic 3:4 crop editor.
8. Add one native SwiftUI template.
9. Add `ImageRenderer` PNG export.
10. Add Vision aesthetic ranking.
11. Add saliency-based auto-crop.
12. Add more templates.
13. Optional later: LLM API / Keychain / caption generation.

## Open Questions For Next Session

- What should the app be named? Listing Studio is just a working name.
- What is the first export format?
  - 3:4 was mentioned, but exact pixel size should be chosen.
  - Possible: 1080×1440, 1080×1350, or a custom house style.
- Should this target real estate only at first, or support other campaign types later?
- Which design template should be built first?
- Should photo ranking pick a fixed number of images, e.g. top 5, top 10, or user-chosen?
- Should the app export a folder of numbered slides, a PDF, or both?
- Is there a specific brokerage/brand color palette/logo to include?

## Relationship To Current Ditto Work

Relevant Ditto features that may inspire Listing Studio:

- Native macOS SwiftUI app structure.
- Custom About and Help windows.
- Settings window.
- Menu bar polish and command menus.
- Import/export and share-link ideas.
- App icon / sibling visual design.

But do not copy Ditto's data model directly. Listing Studio is project/campaign-oriented, not snippet-oriented.

