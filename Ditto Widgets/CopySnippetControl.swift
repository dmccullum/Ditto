//
//  CopySnippetControl.swift
//  Ditto Widgets
//
//  A control that copies one chosen snippet. iOS: Control Center, the Lock
//  Screen, and the Action button. macOS: Control Center and the menu bar.
//

import SwiftUI
import WidgetKit
import AppIntents

struct CopySnippetControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "CopySnippetControl", provider: Provider()) { snippet in
            // An unset or deleted snippet still needs an action; copying an
            // unknown id fails with "That snippet no longer exists."
            ControlWidgetButton(action: CopySnippetIntent(snippet: snippet ?? .missing)) {
                Label(snippet?.title ?? "Choose Snippet", systemImage: "doc.on.doc")
                    .controlWidgetActionHint("Copy")
            }
        }
        .displayName("Copy Snippet")
        .description("Copies the snippet you choose.")
        .promptsForUserConfiguration()
    }

    struct Provider: AppIntentControlValueProvider {
        func previewValue(configuration: CopySnippetControlConfiguration) -> SnippetEntity? {
            configuration.snippet
        }

        /// Look the snippet up again so a rename shows on the control.
        func currentValue(configuration: CopySnippetControlConfiguration) async throws -> SnippetEntity? {
            guard let id = configuration.snippet?.id else { return nil }
            return try await SnippetEntityQuery().entities(for: [id]).first
        }
    }
}

private extension SnippetEntity {
    static let missing = SnippetEntity(SnippetItem(id: UUID(), title: "", preview: "",
                                                   colorName: "", symbolName: ""))
}
