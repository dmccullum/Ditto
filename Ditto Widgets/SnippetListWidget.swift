//
//  SnippetListWidget.swift
//  Ditto Widgets
//
//  Home Screen / desktop widget listing snippets. Every row is a button that
//  copies its snippet without opening the app. Edit Widget picks the list:
//  Pinned (topped up with most copied), Most Copied, Recently Copied, or a
//  category.
//

import SwiftUI
import WidgetKit
import AppIntents

struct SnippetListWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SnippetList", intent: SnippetListConfiguration.self,
                               provider: SnippetListProvider()) { entry in
            SnippetListView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Snippets")
        .description("Copy a snippet with one tap.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        if #available(iOS 27.0, macOS 27.0, *) {
            families.append(.systemExtraLargePortrait)
        }
        return families
    }
}

// MARK: - Timeline

nonisolated struct SnippetListEntry: TimelineEntry {
    var date: Date
    var heading: String
    var headingSymbol: String
    var items: [SnippetItem]
    /// The snippet copied in the last few seconds, shown with a checkmark.
    var copiedID: UUID?
    /// The app hasn't created the shared store yet.
    var needsApp = false

    static let placeholder = SnippetListEntry(
        date: .now, heading: "Pinned", headingSymbol: "pin.fill",
        items: [
            SnippetItem(id: UUID(), title: "Email signature", preview: "Best, Alex", colorName: "blue", symbolName: "envelope.fill"),
            SnippetItem(id: UUID(), title: "Meeting link", preview: "https://meet.example.com/alex", colorName: "teal", symbolName: "link"),
            SnippetItem(id: UUID(), title: "Address", preview: "1 Infinite Loop, Cupertino", colorName: "orange", symbolName: "house.fill"),
            SnippetItem(id: UUID(), title: "#buildinpublic", preview: "#buildinpublic #indiedev", colorName: "pink", symbolName: "number"),
        ]
    )
}

struct SnippetListProvider: AppIntentTimelineProvider {
    /// How long a copied row keeps its checkmark.
    private static let copiedFeedback: TimeInterval = 3

    nonisolated func placeholder(in context: Context) -> SnippetListEntry {
        .placeholder
    }

    func snapshot(for configuration: SnippetListConfiguration, in context: Context) async -> SnippetListEntry {
        let entry = makeEntry(for: configuration, limit: context.family.snippetLayout.slots)
        // The widget gallery shows the sample list before the app has run.
        return entry.needsApp && context.isPreview ? .placeholder : entry
    }

    func timeline(for configuration: SnippetListConfiguration, in context: Context) async -> Timeline<SnippetListEntry> {
        let entry = makeEntry(for: configuration, limit: context.family.snippetLayout.slots)
        // The app reloads widgets after every save, so no polling is needed.
        guard entry.copiedID != nil else { return Timeline(entries: [entry], policy: .never) }
        var cleared = entry
        cleared.date = entry.date.addingTimeInterval(Self.copiedFeedback)
        cleared.copiedID = nil
        return Timeline(entries: [entry, cleared], policy: .never)
    }

    @MainActor
    private func makeEntry(for configuration: SnippetListConfiguration, limit: Int) -> SnippetListEntry {
        let (heading, symbol) = Self.heading(for: configuration)
        guard WidgetStore.container != nil else {
            return SnippetListEntry(date: .now, heading: heading, headingSymbol: symbol, items: [], needsApp: true)
        }
        let snippets = Array(WidgetStore.snippets(from: configuration.source,
                                                  category: configuration.category?.id).prefix(limit))
        let recentCutoff = Date.now.addingTimeInterval(-Self.copiedFeedback)
        let copied = snippets
            .filter { ($0.lastCopiedAt ?? .distantPast) > recentCutoff }
            .max { ($0.lastCopiedAt ?? .distantPast) < ($1.lastCopiedAt ?? .distantPast) }
        return SnippetListEntry(date: .now, heading: heading, headingSymbol: symbol,
                                items: snippets.map(WidgetStore.item), copiedID: copied?.uuid)
    }

    private static func heading(for configuration: SnippetListConfiguration) -> (String, String) {
        switch configuration.source {
        case .pinned:     ("Pinned", "pin.fill")
        case .mostCopied: ("Most Copied", "chart.bar.fill")
        case .recent:     ("Recent", "clock")
        case .category:   (configuration.category?.name ?? "Category",
                           configuration.category?.symbolName ?? "tag.fill")
        }
    }
}

// MARK: - Layout

struct SnippetLayout {
    var columns: Int
    var rows: Int
    var showsPreview: Bool
    var slots: Int { columns * rows }
}

extension WidgetFamily {
    var snippetLayout: SnippetLayout {
        switch self {
        case .systemSmall:      SnippetLayout(columns: 1, rows: 3, showsPreview: false)
        case .systemMedium:     SnippetLayout(columns: 2, rows: 2, showsPreview: true)
        case .systemLarge:      SnippetLayout(columns: 1, rows: 6, showsPreview: true)
        case .systemExtraLarge: SnippetLayout(columns: 2, rows: 6, showsPreview: true)
        default:
            if #available(iOS 27.0, macOS 27.0, *), self == .systemExtraLargePortrait {
                SnippetLayout(columns: 1, rows: 12, showsPreview: true)
            } else {
                SnippetLayout(columns: 1, rows: 4, showsPreview: true)
            }
        }
    }
}

// MARK: - Views

struct SnippetListView: View {
    let entry: SnippetListEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(entry.heading, systemImage: entry.headingSymbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .widgetAccentable()
            if entry.needsApp {
                message("Open Ditto once to show your snippets here.")
            } else if entry.items.isEmpty {
                message("No snippets here yet.")
            } else {
                grid
            }
        }
    }

    private var grid: some View {
        let layout = family.snippetLayout
        return Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(0..<layout.rows, id: \.self) { row in
                GridRow {
                    ForEach(0..<layout.columns, id: \.self) { column in
                        let index = row * layout.columns + column
                        if index < entry.items.count {
                            let item = entry.items[index]
                            SnippetChip(item: item, showsPreview: layout.showsPreview,
                                        isCopied: item.id == entry.copiedID)
                        } else {
                            // Keep row heights even when the list is short.
                            Color.clear
                        }
                    }
                }
            }
        }
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .multilineTextAlignment(.center)
    }
}

/// One snippet: a tinted button that copies it.
struct SnippetChip: View {
    let item: SnippetItem
    let showsPreview: Bool
    let isCopied: Bool

    private var tint: Color { SnippetColor.color(for: item.colorName) }

    var body: some View {
        Button(intent: CopySnippetIntent(snippet: SnippetEntity(item))) {
            HStack(spacing: 6) {
                Capsule()
                    .fill(tint)
                    .frame(width: 3)
                    .padding(.vertical, 6)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    if showsPreview, isCopied || item.preview != item.title {
                        Text(isCopied ? "Copied" : item.preview)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isCopied ? tint : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(tint.opacity(0.14), in: .rect(cornerRadius: 10))
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy \(item.title)")
    }
}

#Preview(as: .systemMedium) {
    SnippetListWidget()
} timeline: {
    SnippetListEntry.placeholder
}
