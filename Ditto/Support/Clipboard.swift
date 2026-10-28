//
//  Clipboard.swift
//  Ditto
//
//  Thin wrapper over the macOS pasteboard (the system clipboard).
//

import AppKit

enum Clipboard {
    /// Replace the clipboard contents with the given string.
    static func copy(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    /// Several snippets as one clipboard string. Short one-liners (links,
    /// hashtag sets, handles, brief phrases) go one per line; as soon as any
    /// snippet is a paragraph or spans lines, a blank line separates them.
    static func joined(_ texts: [String]) -> String {
        guard texts.count > 1 else { return texts.first ?? "" }
        let trimmed = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return trimmed.joined(separator: trimmed.allSatisfy(isShortLine) ? "\n" : "\n\n")
    }

    private static func isShortLine(_ text: String) -> Bool {
        guard !text.contains(where: \.isNewline) else { return false }
        if text.count <= 80 { return true }
        let words = text.split(whereSeparator: \.isWhitespace)
        if words.allSatisfy({ $0.hasPrefix("#") || $0.hasPrefix("@") }) { return true }
        return words.count == 1 && URL(string: text)?.scheme != nil
    }
}
