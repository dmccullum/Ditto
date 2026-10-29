//
//  AboutSignature.swift
//  Ditto
//
//  The About window's signature moment: the Ditto mark, which splits in two
//  when clicked, as it does on a card's “Copied” overlay.
//

import SwiftUI

struct AboutSignature: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spread: CGFloat = 1
    @State private var opacity: Double = 1

    var body: some View {
        Button(action: play) {
            DittoGlyph(spread: spread)
                .foregroundStyle(.tint)
                .opacity(opacity)
                // Icon size, since it takes the icon's place.
                .frame(width: 96, height: 96)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ditto mark")
        .accessibilityHint("Splits the mark in two, as copying a snippet does.")
    }

    /// Slide the second half back onto the first, then out again. Reduce
    /// Motion fades the mark instead.
    private func play() {
        if reduceMotion {
            opacity = 0.2
            withAnimation(.easeInOut(duration: 0.3)) { opacity = 1 }
        } else {
            spread = 0
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { spread = 1 }
        }
    }
}

#Preview {
    AboutSignature()
        .padding()
}
