//
//  WidgetIntents.swift
//  Ditto Widgets
//
//  App Intents the widgets and controls run. SnippetEntity, CategoryEntity,
//  and CopySnippetIntent mirror the app's types of the same names (same
//  identifiers, same parameter), so the system can run a copy in either
//  process; these versions read the store through WidgetStore.
//

import AppIntents
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Entities

struct SnippetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Snippet"
    static let defaultQuery = SnippetEntityQuery()

    let id: UUID
    let title: String
    let preview: String

    init(_ item: SnippetItem) {
        self.id = item.id
        self.title = item.title
        self.preview = item.preview
    }

    var displayRepresentation: DisplayRepresentation {
        let subtitle: LocalizedStringResource? =
            (preview.isEmpty || preview == title) ? nil : "\(preview)"
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: subtitle,
            image: .init(systemName: "doc.on.doc")
        )
    }
}

struct SnippetEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [SnippetEntity] {
        let wanted = Set(identifiers)
        return WidgetStore.allSnippets()
            .filter { $0.uuid.map(wanted.contains) ?? false }
            .map { SnippetEntity(WidgetStore.item($0)) }
    }

    @MainActor
    func suggestedEntities() async throws -> [SnippetEntity] {
        WidgetStore.ranked(WidgetStore.allSnippets()).map { SnippetEntity(WidgetStore.item($0)) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [SnippetEntity] {
        WidgetStore.allSnippets()
            .filter {
                $0.displayTitle.localizedStandardContains(string) ||
                $0.content.localizedStandardContains(string)
            }
            .map { SnippetEntity(WidgetStore.item($0)) }
    }
}

struct CategoryEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static let defaultQuery = CategoryEntityQuery()

    let id: UUID
    let name: String
    let symbolName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbolName))
    }
}

struct CategoryEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [CategoryEntity] {
        let wanted = Set(identifiers)
        return try await suggestedEntities().filter { wanted.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [CategoryEntity] {
        WidgetStore.allCategories().compactMap { category in
            category.uuid.map { CategoryEntity(id: $0, name: category.name, symbolName: category.symbolName) }
        }
    }
}

/// Which snippets a list widget shows (picked in Edit Widget).
nonisolated enum SnippetSource: String, AppEnum {
    case pinned, mostCopied, recent, category

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Snippets"
    static let caseDisplayRepresentations: [SnippetSource: DisplayRepresentation] = [
        .pinned: DisplayRepresentation(title: "Pinned", subtitle: "Then most copied", image: .init(systemName: "pin.fill")),
        .mostCopied: DisplayRepresentation(title: "Most Copied", image: .init(systemName: "chart.bar.fill")),
        .recent: DisplayRepresentation(title: "Recently Copied", image: .init(systemName: "clock")),
        .category: DisplayRepresentation(title: "Category", image: .init(systemName: "tag.fill")),
    ]
}

// MARK: - Configuration

/// Edit Widget options for the snippet list widget.
struct SnippetListConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Snippets"
    static let description = IntentDescription("Choose which snippets the widget lists.")

    @Parameter(title: "Show", default: .pinned)
    var source: SnippetSource

    @Parameter(title: "Category")
    var category: CategoryEntity?

    static var parameterSummary: some ParameterSummary {
        When(\.$source, .equalTo, .category) {
            Summary {
                \.$source
                \.$category
            }
        } otherwise: {
            Summary {
                \.$source
            }
        }
    }
}

/// Edit Widget option for the single-snippet widget. Left empty, the widget
/// shows the top pinned snippet.
struct SnippetButtonConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Snippet"
    static let description = IntentDescription("Choose the snippet to copy.")

    @Parameter(title: "Snippet")
    var snippet: SnippetEntity?
}

/// The snippet a Copy Snippet control copies.
struct CopySnippetControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Snippet"
    static let description = IntentDescription("Choose the snippet to copy.")

    @Parameter(title: "Snippet")
    var snippet: SnippetEntity?
}

// MARK: - Copy

struct CopySnippetIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Snippet"
    static let description = IntentDescription("Copies a snippet's text to the clipboard.")
    // The app already offers Copy Snippet in Shortcuts; don't list it twice.
    static let isDiscoverable = false

    @Parameter(title: "Snippet")
    var snippet: SnippetEntity

    init() {}

    init(snippet: SnippetEntity) {
        self.snippet = snippet
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let text = WidgetStore.recordCopy(of: snippet.id) else {
            throw WidgetIntentError.snippetNotFound
        }
        #if os(macOS)
        Clipboard.copy(text)
        #else
        UIPasteboard.general.string = text
        #endif
        return .result()
    }
}

enum WidgetIntentError: Error, CustomLocalizedStringResourceConvertible {
    case snippetNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .snippetNotFound: "That snippet no longer exists."
        }
    }
}
