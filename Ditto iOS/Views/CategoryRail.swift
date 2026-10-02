//
//  CategoryRail.swift
//  DittoiOS
//
//  The alternate to the chip bar. At rest it's one glass button stacked
//  above New Snippet, showing the category you're in. Press it and slide up:
//  a rail unfurls like a Dock stack — All nearest your thumb — the icons
//  swell under your finger, a name card rides alongside, and every step
//  ticks. Let go to land. A plain tap opens it for tapping instead.
//
//  Big libraries compress the way the Contacts index does: icons away from
//  your finger become dots, but every category keeps its own slice of the
//  rail, and the magnifier turns dots back into icons as you pass.
//

import SwiftUI
import SwiftData

struct CategoryRail: View {
    @Binding var selection: SidebarSelection
    let categories: [Category]
    let allSnippets: [Snippet]
    var side: RailSide = .right

    var body: some View {
        // Built once per data change. The control below owns all the touch
        // state, so a drag frame never re-walks SwiftData relationships.
        RailControl(items: items, selection: $selection, side: side)
    }

    private var items: [RailItem] {
        var items = [RailItem(id: .all, title: "All Snippets", symbol: "tray.full.fill", tint: .blue,
                              count: allSnippets.count)]
        let pinned = allSnippets.lazy.filter(\.isPinned).count
        if pinned > 0 || selection == .pinned {
            items.append(RailItem(id: .pinned, title: "Pinned", symbol: "pin.fill",
                                  tint: .orange, count: pinned))
        }
        if allSnippets.contains(where: { $0.copyCount > 0 }) || selection == .frequent {
            items.append(RailItem(id: .frequent, title: "Frequent", symbol: "flame.fill",
                                  tint: .red, count: nil))
        }
        for category in categories {
            items.append(RailItem(id: .category(category), title: category.name,
                                  symbol: category.symbolName,
                                  tint: SnippetColor.color(for: category.colorName),
                                  count: category.snippets.count))
        }
        return items
    }
}

struct RailItem {
    let id: SidebarSelection
    let title: String
    let symbol: String
    let tint: Color
    let count: Int?
}

private struct RailControl: View {
    let items: [RailItem]
    @Binding var selection: SidebarSelection
    let side: RailSide

    @State private var isOpen = false
    /// The touch that opened the rail; a tap (no slide) leaves it open.
    @State private var openedByTouch = false
    @State private var touchedRail = false
    /// Finger position measured from the top of the rail, while on it.
    @State private var touchY: CGFloat?
    @State private var hoverIndex: Int?

    // Matches the toolbar's New Snippet button so the two read as a column.
    private let button: CGFloat = 48
    private let edgeInset: CGFloat = 28
    private let gap: CGFloat = 10
    private let padding: CGFloat = 10
    /// Below this row height, off-finger icons become dots.
    private let iconPitch: CGFloat = 24

    private var current: RailItem? { items.first { $0.id == selection } }

    var body: some View {
        GeometryReader { geo in
            let layout = Layout(items: items.count, height: geo.size.height,
                                button: button, gap: gap, padding: padding)
            ZStack(alignment: side == .right ? .bottomTrailing : .bottomLeading) {
                if isOpen {
                    // Dim the library so the rail reads as the focus; tap to dismiss.
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { close() }
                        .transition(.opacity)
                }

                VStack(alignment: side == .right ? .trailing : .leading, spacing: gap) {
                    if isOpen {
                        rail(layout)
                            .transition(.scale(scale: 0.2, anchor: .bottom).combined(with: .opacity))
                    }
                    toggle
                }
                .padding(side == .right ? .trailing : .leading, edgeInset)
                .gesture(drag(layout), including: .all)
            }
            .frame(width: geo.size.width, height: geo.size.height,
                   alignment: side == .right ? .bottomTrailing : .bottomLeading)
            .coordinateSpace(.named("rail"))
        }
        .sensoryFeedback(.selection, trigger: hoverIndex) { _, new in new != nil }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isOpen) { _, open in open }
    }

    // MARK: - Pieces

    private var toggle: some View {
        let tint = current?.tint ?? .blue
        return Image(systemName: isOpen ? "xmark" : (current?.symbol ?? "tray.full.fill"))
            .font(.system(size: isOpen ? 17 : 19, weight: .semibold))
            .foregroundStyle(isOpen ? AnyShapeStyle(.primary) : AnyShapeStyle(tint))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: button, height: button)
            .glassEffect(.regular.interactive(), in: .circle)
            .contentShape(.circle)
            .accessibilityElement()
            .accessibilityLabel("Category Switcher")
            .accessibilityValue(current?.title ?? "")
            .accessibilityHint("Swipe up or down to change category")
            .accessibilityAddTraits(.isButton)
            .accessibilityAdjustableAction { direction in
                guard let index = items.firstIndex(where: { $0.id == selection }) else { return }
                switch direction {
                case .increment: selection = items[min(index + 1, items.count - 1)].id
                case .decrement: selection = items[max(index - 1, 0)].id
                @unknown default: break
                }
            }
    }

    private func rail(_ layout: Layout) -> some View {
        VStack(spacing: 0) {
            // Rows run top-down; items run bottom-up, so All sits by the thumb.
            ForEach(0..<items.count, id: \.self) { row in
                glyph(row: row, layout: layout)
                    .frame(width: button, height: layout.pitch)
            }
        }
        .padding(.vertical, padding)
        .glassEffect(.regular, in: .capsule)
        .overlay(alignment: side == .right ? .topTrailing : .topLeading) {
            if let hoverIndex, let touchY {
                NameCard(item: items[hoverIndex])
                    .alignmentGuide(.top) { $0.height / 2 }
                    .offset(x: side == .right ? -(button + 30) : button + 30,
                            y: min(max(touchY, 24), layout.railHeight - 24))
                    .transition(.scale(scale: 0.85, anchor: side == .right ? .trailing : .leading)
                        .combined(with: .opacity))
            }
        }
        .accessibilityHidden(true)
    }

    private func glyph(row: Int, layout: Layout) -> some View {
        let index = items.count - 1 - row
        let item = items[index]
        let touching = touchY != nil
        let isActive = touching ? hoverIndex == index : item.id == selection
        let center = padding + (CGFloat(row) + 0.5) * layout.pitch
        let swell = magnification(center: center, pitch: layout.pitch)
        let compressed = layout.pitch < iconPitch
        // In a compressed rail, show every Nth icon (plus whatever the
        // magnifier is over); the rest are dots holding their slot.
        let stride = max(1, Int((iconPitch / layout.pitch).rounded(.up)))
        let showsIcon = !compressed || isActive || swell > 1.25 || index % stride == 0
        let tile = min(28, max(layout.pitch, iconPitch) - 4)

        return ZStack {
            if showsIcon {
                RoundedRectangle(cornerRadius: tile * 0.3, style: .continuous)
                    .fill(item.tint.gradient)
                    .opacity(isActive ? 1 : 0)
                Image(systemName: item.symbol)
                    .font(.system(size: tile * 0.5, weight: .bold))
                    .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(item.tint))
            } else {
                Circle()
                    .fill(item.tint)
                    .frame(width: 5, height: 5)
            }
        }
        .frame(width: tile, height: tile)
        .scaleEffect(swell)
        // Swell toward the content and push neighbors apart, Dock-style.
        .offset(x: (side == .right ? -1 : 1) * (swell - 1) * 22,
                y: spread(center: center, pitch: layout.pitch))
        .opacity(touching && !isActive ? 0.85 : 1)
    }

    /// Smooth cosine falloff around the finger. Reach is measured in points
    /// as well as rows, so a dense rail still magnifies a thumb-sized patch.
    private func magnification(center: CGFloat, pitch: CGFloat) -> CGFloat {
        guard let touchY else { return 1 }
        let reach = max(pitch * 2.6, 70)
        let distance = min(abs(center - touchY) / reach, 1)
        return 1 + 0.6 * (cos(distance * .pi) + 1) / 2
    }

    private func spread(center: CGFloat, pitch: CGFloat) -> CGFloat {
        guard let touchY else { return 0 }
        let offset = center - touchY
        let sigma = max(pitch * 1.6, 44)
        return offset * 0.45 * exp(-(offset * offset) / (2 * sigma * sigma))
    }

    // MARK: - Gesture

    private func drag(_ layout: Layout) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("rail"))
            .onChanged { value in
                if !isOpen {
                    openedByTouch = true
                    withAnimation(.bouncy(duration: 0.32, extraBounce: 0.08)) { isOpen = true }
                }
                // Where the rail sits in the container (it grows up from the button).
                let railBottom = layout.height - button - gap
                let railTop = railBottom - layout.railHeight
                let y = value.location.y
                if y >= railTop - 30 && y <= railBottom + 6 {
                    let local = min(max(y - railTop, padding), layout.railHeight - padding - 0.01)
                    let row = min(max(Int((local - padding) / layout.pitch), 0), items.count - 1)
                    let index = items.count - 1 - row
                    touchedRail = true
                    if touchY == nil {
                        withAnimation(.snappy(duration: 0.2)) { touchY = local; hoverIndex = index }
                    } else {
                        touchY = local
                        if hoverIndex != index { hoverIndex = index }
                    }
                } else if touchY != nil {
                    // Slid back down onto the button: nothing chosen yet.
                    withAnimation(.snappy(duration: 0.2)) { touchY = nil; hoverIndex = nil }
                }
            }
            .onEnded { _ in
                if let hoverIndex {
                    selection = items[hoverIndex].id
                    close()
                } else if openedByTouch && !touchedRail {
                    // A tap: stay open so the rail can be tapped.
                    openedByTouch = false
                } else {
                    close()
                }
            }
    }

    private func close() {
        withAnimation(.snappy(duration: 0.28)) {
            isOpen = false
            touchY = nil
            hoverIndex = nil
        }
        openedByTouch = false
        touchedRail = false
    }
}

/// Row height for the open rail: as roomy as the screen allows, shrinking
/// (into index-style dots) when the library is big.
private struct Layout {
    let items: Int
    let height: CGFloat
    let button: CGFloat
    let gap: CGFloat
    let padding: CGFloat

    var pitch: CGFloat {
        let available = height - button - gap - padding * 2 - 12
        return min(38, max(6, available / CGFloat(max(items, 1))))
    }

    var railHeight: CGFloat { pitch * CGFloat(items) + padding * 2 }
}

/// The floating card that names the category under your thumb.
private struct NameCard: View {
    let item: RailItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(item.tint.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.headline)
                    .fontDesign(.rounded)
                    .lineLimit(1)
                if let count = item.count {
                    Text(count == 1 ? "1 snippet" : "\(count) snippets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .fixedSize()
        .glassEffect(.regular.tint(item.tint.opacity(0.25)), in: .capsule)
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .allowsHitTesting(false)
    }
}
