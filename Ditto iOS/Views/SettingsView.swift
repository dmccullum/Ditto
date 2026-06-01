//
//  SettingsView.swift
//  DittoiOS
//
//  In-app settings, presented as a sheet from the sidebar.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
