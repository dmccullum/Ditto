//
//  CategoryChip.swift
//  DittoiOS
//

import SwiftUI

/// A tinted capsule: soft tint when idle, filled with the tint when selected.
/// Used by the snippet and category editors.
struct CategoryChip: View {
    let title: String
    let symbol: String
    let tint: Color
    var count: Int? = nil
    var isSelected = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .imageScale(.medium)
            Text(title)
                .lineLimit(1)
            if let count {
                Text("\(count)")
                    .monospacedDigit()
                    .opacity(0.65)
            }
        }
        .font(.subheadline.weight(.semibold))
        .fontDesign(.rounded)
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(isSelected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.15)))
        }
        .overlay {
            Capsule().strokeBorder(tint.opacity(isSelected ? 0 : 0.22), lineWidth: 1)
        }
        .contentShape(Capsule())
    }
}
