//
//  Clipboard.swift
//  QuickCopy 2
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
}
