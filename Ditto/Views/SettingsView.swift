//
//  SettingsView.swift
//  QuickCopy 2 (Ditto)
//
//  The Settings (⌘,) window.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Query private var snippets: [Snippet]
    @Query private var categories: [Category]
    @State private var launchAtLogin = LoginItem.isEnabled

    private var totalCopies: Int { snippets.reduce(0) { $0 + $1.copyCount } }

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Library") {
                LabeledContent("Snippets", value: snippets.count.formatted())
                LabeledContent("Categories", value: categories.count.formatted())
                LabeledContent("Copies", value: totalCopies.formatted())
            }

            Section("General") {
                Toggle("Launch Ditto at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        LoginItem.setEnabled(enabled)
                    }
            }

            Section("Shared Links") {
                Picker("Imported snippets", selection: $settings.linkCategoryBehavior) {
                    ForEach(LinkCategoryBehavior.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                Text("When you open a ditto:// link, choose whether to keep the snippet's original category or add it as uncategorized.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 400)
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings())
        .modelContainer(for: [Snippet.self, Category.self], inMemory: true)
}
