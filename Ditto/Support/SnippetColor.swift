//
//  SnippetColor.swift
//  Ditto
//
//  A small, friendly palette. We store the *name* (a String) in the model and
//  resolve it to a real SwiftUI Color here, so the database stays simple.
//

import SwiftUI

enum SnippetColor: String, CaseIterable, Identifiable {
    // Declared in hue order so the picker grid reads like a palette.
    // System colors adapt to light/dark; the custom shades are fixed
    // mid-tones chosen to hold up in both modes.
    case red, coral, orange, gold, yellow, lime, green, forest, mint, teal,
         cyan, sky, blue, navy, indigo, lavender, purple, plum, pink, rose,
         brown, slate

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red:      return .red
        case .coral:    return Color(red: 1.00, green: 0.45, blue: 0.40)
        case .orange:   return .orange
        case .gold:     return Color(red: 0.85, green: 0.65, blue: 0.13)
        case .yellow:   return .yellow
        case .lime:     return Color(red: 0.55, green: 0.76, blue: 0.22)
        case .green:    return .green
        case .forest:   return Color(red: 0.18, green: 0.54, blue: 0.34)
        case .mint:     return .mint
        case .teal:     return Color(red: 0.00, green: 0.52, blue: 0.56)
        case .cyan:     return .cyan
        case .sky:      return Color(red: 0.39, green: 0.58, blue: 0.93)
        case .blue:     return .blue
        case .navy:     return Color(red: 0.20, green: 0.32, blue: 0.62)
        case .indigo:   return .indigo
        case .lavender: return Color(red: 0.62, green: 0.54, blue: 0.93)
        case .purple:   return .purple
        case .plum:     return Color(red: 0.56, green: 0.27, blue: 0.52)
        case .pink:     return .pink
        case .rose:     return Color(red: 0.91, green: 0.27, blue: 0.55)
        case .brown:    return .brown
        case .slate:    return Color(red: 0.45, green: 0.51, blue: 0.58)
        }
    }

    var displayName: String { rawValue.capitalized }

    /// Resolve a stored color name back to a Color, defaulting to blue.
    static func color(for name: String) -> Color {
        SnippetColor(rawValue: name)?.color ?? .blue
    }
}

@MainActor
extension Snippet {
    /// The snippet's category color. Uncategorized snippets use the app's
    /// accent, so a system accent the user picked still wins.
    var tint: Color {
        category.map { SnippetColor.color(for: $0.colorName) } ?? .accentColor
    }
}

/// A curated set of SF Symbols that read well as category icons.
enum CategorySymbol {
    /// A symbol name as VoiceOver should read it: "envelope.fill" → "envelope".
    static func spokenName(for symbol: String) -> String {
        symbol.split(separator: ".")
            .filter { $0 != "fill" }
            .joined(separator: " ")
    }

    static let options: [String] = [
        // Text & writing
        "textformat", "paragraph", "square.and.pencil", "note.text",
        "text.alignleft", "text.cursor", "signature", "character",

        // Code & technical
        "curlybraces", "terminal.fill", "function", "command", "keyboard",
        "gearshape.fill", "cpu", "qrcode", "ladybug.fill",

        // Security
        "lock.fill", "key.fill", "shield.fill",

        // Lists & structure
        "list.bullet", "list.number", "checklist", "list.clipboard",

        // Documents
        "doc.text.fill", "text.quote", "number", "paperclip",

        // Links & social
        "link", "at", "bubble.left.fill", "megaphone.fill", "envelope.fill",
        "phone.fill", "paperplane.fill", "bell.fill", "wifi",

        // Creative & media
        "wand.and.stars", "sparkles", "arrow.triangle.2.circlepath",
        "paintpalette.fill", "camera.fill", "music.note", "photo.fill",
        "film.fill", "tv.fill", "headphones", "mic.fill", "guitars.fill",
        "theatermasks.fill",

        // Organisation
        "tag.fill", "bookmark.fill", "star.fill", "heart.fill",
        "bolt.fill", "flame.fill", "calendar", "clock",

        // Work & money
        "briefcase.fill", "building.2.fill", "chart.bar.fill",
        "chart.line.uptrend.xyaxis", "dollarsign.circle.fill",
        "creditcard.fill", "cart.fill", "shippingbox.fill",

        // Home & life
        "house.fill", "car.fill", "fork.knife", "cup.and.saucer.fill",
        "cross.case.fill", "pills.fill", "dumbbell.fill", "lightbulb.fill",
        "hammer.fill", "scissors", "umbrella.fill", "leaf.fill",

        // Travel & places
        "airplane", "map.fill", "suitcase.fill", "tent.fill",
        "sailboat.fill", "globe",

        // Learning
        "graduationcap.fill", "book.fill", "brain.head.profile", "atom",

        // People
        "person.fill", "person.2.fill",

        // Games & celebration
        "gamecontroller.fill", "dice.fill", "puzzlepiece.fill",
        "face.smiling.fill", "party.popper.fill", "balloon.2.fill",
        "gift.fill", "crown.fill", "trophy.fill", "birthday.cake.fill",

        // Nature & critters
        "sun.max.fill", "moon.stars.fill", "snowflake", "rainbow",
        "fireworks", "pawprint.fill", "cat.fill", "dog.fill", "bird.fill",
        "fish.fill", "hare.fill", "tortoise.fill", "teddybear.fill",
    ]
}
