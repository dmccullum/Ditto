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
