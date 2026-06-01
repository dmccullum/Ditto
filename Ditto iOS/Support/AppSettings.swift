//
//  AppSettings.swift
//  DittoiOS
//
//  UserDefaults-backed preferences for the iOS app.
//

import SwiftUI

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

/// How the snippet list groups its rows.
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

/// Observable, UserDefaults-backed preferences.
@Observable
final class AppSettings {
    /// How the All Snippets list groups its rows.
    var grouping: SnippetGrouping {
        didSet { UserDefaults.standard.set(grouping.rawValue, forKey: "snippetGrouping") }
    }

    /// What to do with a category carried by an imported ditto:// link.
    var linkCategoryBehavior: LinkCategoryBehavior {
        didSet { UserDefaults.standard.set(linkCategoryBehavior.rawValue, forKey: "linkCategoryBehavior") }
    }

    init() {
        grouping = UserDefaults.standard.string(forKey: "snippetGrouping")
            .flatMap(SnippetGrouping.init) ?? .none
        linkCategoryBehavior = UserDefaults.standard.string(forKey: "linkCategoryBehavior")
            .flatMap(LinkCategoryBehavior.init) ?? .keep
    }
}
