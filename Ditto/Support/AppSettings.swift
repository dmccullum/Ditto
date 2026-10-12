//
//  AppSettings.swift
//  Ditto
//
//  User preferences plus small helpers for launch-at-login and pasting.
//

import SwiftUI
import ServiceManagement

/// What to do with a shared link's category when importing it.
enum LinkCategoryBehavior: String, CaseIterable, Identifiable {
    case keep
    case uncategorized

    var id: String { rawValue }

    var label: String {
        switch self {
        case .keep:          return "Keep their category"
        case .uncategorized: return "Import as uncategorized"
        }
    }
}

/// How the All Snippets view groups its cards.
enum SnippetGrouping: String, CaseIterable, Identifiable {
    case none
    case category
    case dateAdded

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:      return "None"
        case .category:  return "Category"
        case .dateAdded: return "Date Added"
        }
    }
}

/// Observable, UserDefaults-backed preferences shared across every scene.
@Observable
final class AppSettings {
    /// Section titles the user has collapsed in the menu bar dropdown.
    var collapsedSections: Set<String> {
        didSet { UserDefaults.standard.set(Array(collapsedSections), forKey: "collapsedSections") }
    }

    /// How the All Snippets view groups its cards.
    var grouping: SnippetGrouping {
        didSet { UserDefaults.standard.set(grouping.rawValue, forKey: "snippetGrouping") }
    }

    /// What to do with a category carried by an imported ditto:// link.
    var linkCategoryBehavior: LinkCategoryBehavior {
        didSet { UserDefaults.standard.set(linkCategoryBehavior.rawValue, forKey: "linkCategoryBehavior") }
    }

    init() {
        collapsedSections = Set(UserDefaults.standard.stringArray(forKey: "collapsedSections") ?? [])
        grouping = UserDefaults.standard.string(forKey: "snippetGrouping")
            .flatMap(SnippetGrouping.init) ?? .none
        linkCategoryBehavior = UserDefaults.standard.string(forKey: "linkCategoryBehavior")
            .flatMap(LinkCategoryBehavior.init) ?? .keep
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
