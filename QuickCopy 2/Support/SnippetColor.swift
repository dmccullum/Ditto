//
//  SnippetColor.swift
//  QuickCopy 2
//
//  A small, friendly palette. We store the *name* (a String) in the model and
//  resolve it to a real SwiftUI Color here, so the database stays simple.
//

import SwiftUI

enum SnippetColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red:    return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green:  return .green
        case .mint:   return .mint
        case .teal:   return .teal
        case .cyan:   return .cyan
        case .blue:   return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink:   return .pink
        case .brown:  return .brown
        }
    }

    var displayName: String { rawValue.capitalized }

    /// Resolve a stored color name back to a Color, defaulting to blue.
    static func color(for name: String) -> Color {
        SnippetColor(rawValue: name)?.color ?? .blue
    }
}

/// A curated set of SF Symbols that read well as category icons.
enum CategorySymbol {
    static let options: [String] = [
        "number", "link", "text.quote", "star.fill", "heart.fill",
        "bolt.fill", "flame.fill", "tag.fill", "bookmark.fill", "megaphone.fill",
        "bubble.left.fill", "at", "calendar", "cart.fill", "globe",
        "paintpalette.fill", "camera.fill", "music.note", "envelope.fill", "person.fill"
    ]
}
