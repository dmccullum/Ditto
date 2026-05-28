//
//  SettingsView.swift
//  QuickCopy 2 (Ditto)
//
//  The Settings (⌘,) window.
//

import SwiftUI

struct SettingsView: View {
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch Ditto at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        LoginItem.setEnabled(enabled)
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 150)
    }
}

#Preview {
    SettingsView()
}
