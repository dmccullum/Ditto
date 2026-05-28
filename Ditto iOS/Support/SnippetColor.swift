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

    static func color(for name: String) -> Color {
        SnippetColor(rawValue: name)?.color ?? .blue
    }
}

enum CategorySymbol {
    static let options: [String] = [
        "textformat", "paragraph", "square.and.pencil", "note.text",
        "text.alignleft", "text.cursor", "signature", "character",
        "curlybraces", "terminal.fill", "function", "command", "keyboard",
        "list.bullet", "list.number", "checklist", "list.clipboard",
        "doc.text.fill", "text.quote", "number",
        "link", "at", "bubble.left.fill", "megaphone.fill", "envelope.fill",
        "wand.and.stars", "sparkles", "arrow.triangle.2.circlepath",
        "paintpalette.fill", "camera.fill", "music.note",
        "tag.fill", "bookmark.fill", "star.fill", "heart.fill",
        "bolt.fill", "flame.fill", "calendar", "clock",
        "person.fill", "person.2.fill", "globe",
    ]
}
