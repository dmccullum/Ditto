//
//  SettingsView.swift
//  QuickCopy 2 (Ditto)
//
//  The Settings (⌘,) window.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        @Bindable var settings = settings
        Form {
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
        .frame(width: 460, height: 260)
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings())
}
