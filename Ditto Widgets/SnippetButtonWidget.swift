//
//  SnippetButtonWidget.swift
//  Ditto Widgets
//
//  One snippet, one tap to copy. Small Home Screen / desktop widget, plus
//  the circular and rectangular Lock Screen widgets on iOS. Edit Widget
//  picks the snippet; left empty it shows the top pinned snippet.
//

import SwiftUI
import WidgetKit
import AppIntents

struct SnippetButtonWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SnippetButton", intent: SnippetButtonConfiguration.self,
                               provider: SnippetButtonProvider()) { entry in
            SnippetButtonView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Copy Snippet")
        #if os(macOS)
        .description("Copy one snippet with a click.")
        #else
        .description("Copy one snippet with a tap.")
        #endif
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .accessoryCircular, .accessoryRectangular]
        #else
        [.systemSmall]
        #endif
    }
}

// MARK: - Timeline

nonisolated struct SnippetButtonEntry: TimelineEntry {
    var date: Date
    var item: SnippetItem?
    var isCopied = false
    var needsApp = false

    static let placeholder = SnippetButtonEntry(
        date: .now,
        item: SnippetItem(id: UUID(), title: "Email signature", preview: "Best, Alex",
                          colorName: "blue", symbolName: "envelope.fill")
    )
}

struct SnippetButtonProvider: AppIntentTimelineProvider {
    private static let copiedFeedback: TimeInterval = 3

    nonisolated func placeholder(in context: Context) -> SnippetButtonEntry {
        .placeholder
    }

    func snapshot(for configuration: SnippetButtonConfiguration, in context: Context) async -> SnippetButtonEntry {
        let entry = makeEntry(for: configuration)
        return entry.item == nil && context.isPreview ? .placeholder : entry
    }

    func timeline(for configuration: SnippetButtonConfiguration, in context: Context) async -> Timeline<SnippetButtonEntry> {
        let entry = makeEntry(for: configuration)
        guard entry.isCopied else { return Timeline(entries: [entry], policy: .never) }
        var cleared = entry
        cleared.date = entry.date.addingTimeInterval(Self.copiedFeedback)
        cleared.isCopied = false
        return Timeline(entries: [entry, cleared], policy: .never)
    }

    @MainActor
    private func makeEntry(for configuration: SnippetButtonConfiguration) -> SnippetButtonEntry {
        guard WidgetStore.container != nil else {
            return SnippetButtonEntry(date: .now, needsApp: true)
        }
        let snippet = configuration.snippet.flatMap { WidgetStore.snippet(id: $0.id) }
            ?? WidgetStore.ranked(WidgetStore.allSnippets()).first
        let isCopied = (snippet?.lastCopiedAt ?? .distantPast) > .now.addingTimeInterval(-Self.copiedFeedback)
        return SnippetButtonEntry(date: .now, item: snippet.map(WidgetStore.item), isCopied: isCopied)
    }
}

// MARK: - Views

struct SnippetButtonView: View {
    let entry: SnippetButtonEntry
    @Environment(\.widgetFamily) private var family

    #if os(macOS)
    private static let copyHint: LocalizedStringKey = "Click to copy"
    #else
    private static let copyHint: LocalizedStringKey = "Tap to copy"
    #endif

    var body: some View {
        if let item = entry.item {
            Button(intent: CopySnippetIntent(snippet: SnippetEntity(item))) {
                content(for: item)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy \(item.title)")
        } else {
            Text(entry.needsApp ? "Open Ditto to set up" : "No snippets yet")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private func content(for item: SnippetItem) -> some View {
        let symbol = entry.isCopied ? "checkmark" : "doc.on.doc"
        switch family {
        #if os(iOS)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: entry.isCopied ? "checkmark" : item.symbolName)
                        .font(.title3)
                    Text(item.title)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label(item.title, systemImage: symbol)
                    .font(.headline)
                    .lineLimit(1)
                    .widgetAccentable()
                Text(entry.isCopied ? "Copied" : item.preview)
                    .font(.caption)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        #endif
        default:
            let tint = SnippetColor.color(for: item.colorName)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: item.symbolName)
                        .foregroundStyle(tint)
                        .widgetAccentable()
                    Spacer()
                    Image(systemName: symbol)
                        .foregroundStyle(entry.isCopied ? tint : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .font(.headline)
                Spacer(minLength: 0)
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                if item.preview != item.title {
                    Text(item.preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Text(entry.isCopied ? "Copied" : Self.copyHint)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
    }
}

#Preview(as: .systemSmall) {
    SnippetButtonWidget()
} timeline: {
    SnippetButtonEntry.placeholder
}
