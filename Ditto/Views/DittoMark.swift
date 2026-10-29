//
//  DittoMark.swift
//  Ditto (shared with the iOS target)
//
//  The app icon's mark — two identical "D" halves, one offset from the other —
//  drawn natively so it can live in the UI and animate. `spread` slides the
//  second half from sitting on top of the first (0) out to the icon's resting
//  position (1): a snippet becoming two, which is the whole idea of the app.
//

import SwiftUI
import AppKit

/// One half of the mark, traced from the icon's SVG (1024×1024 artboard).
/// The second half is the first rotated 180° and shifted down-right.
nonisolated struct DittoMarkHalf: Shape {
    var isSecond = false
    var spread: CGFloat = 1

    var animatableData: CGFloat {
        get { spread }
        set { spread = newValue }
    }

    // Bounding box of both halves on the artboard, used to fit the mark.
    private static let bounds = CGRect(x: 151.57, y: 156.52, width: 720.33, height: 710.61)
    // Center of the first half, and how far the second half sits from it.
    private static let center = CGPoint(x: 399.8, y: 404.17)
    private static let offset = CGSize(width: 223.87, height: 215.31)

    func path(in rect: CGRect) -> Path {
        var half = Path()
        half.move(to: CGPoint(x: 578, y: 156.52))
        half.addLine(to: CGPoint(x: 398.38, y: 156.52))
        half.addCurve(to: CGPoint(x: 151.57, y: 403.33),
                      control1: CGPoint(x: 262.07, y: 156.52),
                      control2: CGPoint(x: 151.57, y: 267.02))
        half.addCurve(to: CGPoint(x: 400.06, y: 651.82),
                      control1: CGPoint(x: 151.57, y: 540.57),
                      control2: CGPoint(x: 262.82, y: 651.82))
        half.addLine(to: CGPoint(x: 576.84, y: 651.82))
        half.addCurve(to: CGPoint(x: 646.87, y: 581.79),
                      control1: CGPoint(x: 615.52, y: 651.82),
                      control2: CGPoint(x: 646.87, y: 620.47))
        half.addLine(to: CGPoint(x: 646.87, y: 225.39))
        half.addCurve(to: CGPoint(x: 578, y: 156.52),
                      control1: CGPoint(x: 646.87, y: 187.36),
                      control2: CGPoint(x: 616.04, y: 156.52))
        half.closeSubpath()

        if isSecond {
            let c = Self.center
            let flip = CGAffineTransform(translationX: c.x, y: c.y)
                .rotated(by: .pi)
                .translatedBy(x: -c.x, y: -c.y)
            let slide = CGAffineTransform(translationX: Self.offset.width * spread,
                                          y: Self.offset.height * spread)
            half = half.applying(flip.concatenating(slide))
        }

        // Fit the artboard bounds into rect, preserving aspect ratio.
        let b = Self.bounds
        let scale = min(rect.width / b.width, rect.height / b.height)
        let fitted = CGSize(width: b.width * scale, height: b.height * scale)
        let origin = CGPoint(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2)
        let fit = CGAffineTransform(translationX: -b.minX, y: -b.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: origin.x, y: origin.y))
        return half.applying(fit)
    }
}

/// The two-tone glyph on its own, in a single color (e.g. white on an accent).
struct DittoGlyph: View {
    var spread: CGFloat = 1

    var body: some View {
        ZStack {
            // The back half is faded so the solid lower-right half reads as
            // the front one, matching the icon.
            DittoMarkHalf(spread: spread)
                .opacity(0.6)
            DittoMarkHalf(isSecond: true, spread: spread)
        }
        .accessibilityHidden(true)
    }
}

/// The full-color mark on the icon's blue-to-teal tile.
struct DittoMarkTile: View {
    var size: CGFloat = 64
    var spread: CGFloat = 1
    /// Slides the front half this far and the back half a third as far the
    /// other way, so the copy peeks out from behind the original (About's
    /// pointer parallax). Zero is the icon's resting art.
    var parallax: CGSize = .zero

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(red: 0.00, green: 0.38, blue: 1.00),
                         Color(red: 0.29, green: 0.77, blue: 0.77)],
                startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 1.2)
            ))
            .overlay {
                ZStack {
                    DittoMarkHalf(spread: spread)
                        .fill(LinearGradient(
                            colors: [Color(red: 0.70, green: 0.84, blue: 1.00),
                                     Color(red: 0.50, green: 0.65, blue: 1.00)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .offset(x: -parallax.width / 3, y: -parallax.height / 3)
                    DittoMarkHalf(isSecond: true, spread: spread)
                        .fill(LinearGradient(
                            colors: [Color(red: 0.70, green: 0.93, blue: 1.00),
                                     Color(red: 0.93, green: 1.00, blue: 0.98)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .opacity(0.85)
                        .shadow(color: .black.opacity(0.18), radius: size * 0.04, y: size * 0.02)
                        .offset(parallax)
                }
                .padding(size * 0.17)
            }
            .shadow(color: Color(red: 0.0, green: 0.38, blue: 1.0).opacity(0.3),
                    radius: size * 0.18, y: size * 0.08)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension NSImage {
    /// The glyph as a menu bar template image, so it matches the app icon and
    /// takes on the menu bar's own color (the faded back half stays dimmer).
    @MainActor static let dittoMenuBarGlyph: NSImage = {
        let renderer = ImageRenderer(content: MenuBarGlyph())
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "doc.on.clipboard.fill",
                                                accessibilityDescription: "Ditto")!
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }()
}

/// The glyph at menu bar size. A named type rather than an opaque
/// `some View`, so its main-actor `View` conformance is known to the renderer.
private struct MenuBarGlyph: View {
    var body: some View {
        DittoGlyph()
            .foregroundStyle(.black)
            .frame(width: 16, height: 16)
    }
}

#Preview {
    VStack(spacing: 30) {
        DittoMarkTile(size: 120)
        DittoMarkTile(size: 120, spread: 0)
        DittoGlyph().frame(width: 40, height: 40).foregroundStyle(.blue)
    }
}
