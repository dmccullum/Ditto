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
        // Text & writing
        "textformat", "paragraph", "square.and.pencil", "note.text",
        "text.alignleft", "text.cursor", "signature", "character",

        // Code & technical
        "curlybraces", "terminal.fill", "function", "command", "keyboard",

        // Lists & structure
        "list.bullet", "list.number", "checklist", "list.clipboard",

        // Documents
        "doc.text.fill", "text.quote", "number",

        // Links & social
        "link", "at", "bubble.left.fill", "megaphone.fill", "envelope.fill",

        // Creative & content
        "wand.and.stars", "sparkles", "arrow.triangle.2.circlepath",
        "paintpalette.fill", "camera.fill", "music.note",

        // Organisation
        "tag.fill", "bookmark.fill", "star.fill", "heart.fill",
        "bolt.fill", "flame.fill", "calendar", "clock",

        // People & world
        "person.fill", "person.2.fill", "globe",
    ]
}
