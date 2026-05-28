//
//  AppSettings.swift
//  QuickCopy 2 (Ditto)
//
//  User preferences plus small helpers for launch-at-login and pasting.
//

import SwiftUI
import ServiceManagement

/// Observable, UserDefaults-backed preferences shared across every scene.
@Observable
final class AppSettings {
    /// Section titles the user has collapsed in the menu bar dropdown.
    var collapsedSections: Set<String> {
        didSet { UserDefaults.standard.set(Array(collapsedSections), forKey: "collapsedSections") }
    }

    init() {
        collapsedSections = Set(UserDefaults.standard.stringArray(forKey: "collapsedSections") ?? [])
    }
}

/// Wraps the system "open at login" registration.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("Ditto: failed to update login item: \(error)")
        }
    }
}
