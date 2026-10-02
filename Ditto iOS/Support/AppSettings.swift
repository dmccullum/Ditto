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

/// Which edge the category rail sits on — the thumb side.
enum RailSide: String, CaseIterable, Identifiable {
    case right
    case left

    var id: String { rawValue }
    var label: String { self == .right ? "Right" : "Left" }
    var edge: HorizontalEdge { self == .right ? .trailing : .leading }
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

    /// Right for right thumbs; left for the left-handed.
    var railSide: RailSide {
        didSet { UserDefaults.standard.set(railSide.rawValue, forKey: "railSide") }
    }

    init() {
        grouping = UserDefaults.standard.string(forKey: "snippetGrouping")
            .flatMap(SnippetGrouping.init) ?? .none
        linkCategoryBehavior = UserDefaults.standard.string(forKey: "linkCategoryBehavior")
            .flatMap(LinkCategoryBehavior.init) ?? .keep
        railSide = UserDefaults.standard.string(forKey: "railSide")
            .flatMap(RailSide.init) ?? .right
    }
}
