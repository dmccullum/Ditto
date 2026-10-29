//
//  AboutSignature.swift
//  Ditto
//
//  The About window's signature moment: the Ditto mark on its icon tile, which
//  makes copies of itself. The mark's two halves (original and copy) shift
//  apart toward the pointer. Clicking the mark peels a copy off onto a fanned
//  stack beside it, up to five; dragging a copy away flings it off, clicking
//  the stack gathers the copies back into the mark, and Edit › Undo (⌘Z) takes
//  back the last of any of these.
//

import AppKit
import DMKit
import SwiftUI

struct AboutSignature: View {
    @Environment(\.aboutPointerLocation) private var pointer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.undoManager) private var undoManager
    @State private var stack = CopyStack()
    @State private var spread: CGFloat = 1
    @State private var markOpacity: Double = 1
    /// The signature's frame in the space `aboutPointerLocation` is measured in, to place the pointer against the mark.
    @State private var frameInWindow: CGRect = .zero

    static let size = CGSize(width: 330, height: 128)
    static let markSize: CGFloat = 96
    static let markCenter = CGPoint(x: size.width / 2, y: 62)

    var body: some View {
        ZStack {
            mark
            ForEach(Array(stack.copies.enumerated()), id: \.element.id) { index, copy in
                CopyTile(copy: copy,
                         slot: stack.slot(of: copy, at: index),
                         reduceMotion: reduceMotion,
                         increasedContrast: contrast == .increased,
                         onGather: { stack.gatherAll(reduceMotion: reduceMotion) },
                         onDrag: { stack.drag(copy.id, by: $0) },
                         onRelease: { stack.release(copy.id, translation: $0, predicted: $1, reduceMotion: reduceMotion) })
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: AboutView<EmptyView>.pointerSpace) } action: { frameInWindow = $0 }
        .onAppear { stack.undoManager = undoManager }
        .onChange(of: undoManager) { _, manager in stack.undoManager = manager }
        .onDisappear { stack.forgetUndo() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ditto mark")
        .accessibilityValue(stack.count == 1 ? "1 copy" : "\(stack.count) copies")
        .accessibilityHint("Makes a copy of the mark, as copying a snippet does.")
        .accessibilityAction { makeCopy() }
        .accessibilityAction(named: "Copy") { makeCopy() }
        .accessibilityAction(named: "Gather Copies") { stack.gatherAll(reduceMotion: reduceMotion) }
    }

    private var mark: some View {
        Button(action: makeCopy) {
            DittoMarkTile(size: Self.markSize, spread: spread, parallax: parallax(scale: 5))
                .overlay { contrastStroke(size: Self.markSize) }
                .opacity(markOpacity)
                .rotation3DEffect(.degrees(tilt), axis: (x: -lean.dy, y: lean.dx, z: 0), perspective: 0.6)
                .dmAnimation(.smooth, value: lean)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(Self.markCenter)
    }

    @ViewBuilder
    private func contrastStroke(size: CGFloat) -> some View {
        if contrast == .increased {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .strokeBorder(.primary.opacity(0.5), lineWidth: 1)
        }
    }

    /// Where the pointer is from the mark, as a vector of length 0...1 that
    /// reaches 1 about 180 points out. Zero when it's outside the window or
    /// with Reduce Motion.
    private var lean: CGVector {
        guard !reduceMotion, let pointer, frameInWindow != .zero else { return .zero }
        let offset = CGPoint(x: pointer.x - frameInWindow.minX - Self.markCenter.x,
                             y: pointer.y - frameInWindow.minY - Self.markCenter.y)
        let dx = offset.x / 180, dy = offset.y / 180
        let length = max(1, (dx * dx + dy * dy).squareRoot())
        return CGVector(dx: dx / length, dy: dy / length)
    }

    private var tilt: Double {
        (lean.dx * lean.dx + lean.dy * lean.dy).squareRoot() * 9
    }

    private func parallax(scale: CGFloat) -> CGSize {
        CGSize(width: lean.dx * scale, height: lean.dy * scale)
    }

    private func makeCopy() {
        if reduceMotion {
            markOpacity = 0.4
            withAnimation(.easeInOut(duration: 0.25)) { markOpacity = 1 }
        } else {
            // The halves close up and split again as the copy peels off.
            spread = 0.35
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { spread = 1 }
        }
        stack.copy(reduceMotion: reduceMotion)
    }
}

// MARK: - The stack

/// The copies beside the mark, oldest at the bottom. Every change registers
/// its inverse with the About window's undo manager, so Edit › Undo and Redo
/// step through copies, flings and gathers.
@Observable
final class CopyStack {
    struct Copy: Identifiable, Equatable {
        enum Leaving: Equatable { case gather, fling(CGSize), fade }

        let id = UUID()
        /// The live drag offset while the pointer holds it.
        var drag: CGSize = .zero
        /// Set while it animates away, before it's removed.
        var leaving: Leaving?
        /// Its slot when it started leaving, so the rest can close up under it.
        var leavingSlot = 0
    }

    static let capacity = 5

    private(set) var copies: [Copy] = []
    @ObservationIgnored weak var undoManager: UndoManager?

    /// Copies on the stack, not counting ones on their way out.
    var count: Int { copies.count { $0.leaving == nil } }

    /// The slot a copy sits in: its place among the copies that are staying.
    func slot(of copy: Copy, at index: Int) -> Int {
        if copy.leaving != nil { return copy.leavingSlot }
        return copies[..<index].count { $0.leaving == nil }
    }

    func copy(reduceMotion: Bool) {
        if count >= Self.capacity, let oldest = copies.first(where: { $0.leaving == nil }) {
            remove(oldest.id, .fade, reduceMotion: reduceMotion)
        }
        insert(Copy(), at: copies.count, reduceMotion: reduceMotion)
        undoManager?.setActionName("Copy")
    }

    func gatherAll(reduceMotion: Bool) {
        let staying = copies.filter { $0.leaving == nil }
        guard !staying.isEmpty else { return }
        for copy in staying.reversed() { remove(copy.id, .gather, reduceMotion: reduceMotion) }
        undoManager?.setActionName("Gather Copies")
    }

    func drag(_ id: UUID, by translation: CGSize) {
        guard let index = copies.firstIndex(where: { $0.id == id && $0.leaving == nil }) else { return }
        copies[index].drag = translation
    }

    /// Lets go of a dragged copy: thrown far or fast enough, it flies off;
    /// otherwise it springs back into its slot.
    func release(_ id: UUID, translation: CGSize, predicted: CGSize, reduceMotion: Bool) {
        guard let index = copies.firstIndex(where: { $0.id == id && $0.leaving == nil }) else { return }
        let distance = hypot(translation.width, translation.height)
        let throwDistance = hypot(predicted.width, predicted.height)
        if distance > 60 || throwDistance > 160 {
            let direction = throwDistance > distance ? predicted : translation
            let length = max(1, hypot(direction.width, direction.height))
            let far = CGSize(width: direction.width / length * 420, height: direction.height / length * 420)
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            remove(id, .fling(far), reduceMotion: reduceMotion)
            undoManager?.setActionName("Remove Copy")
        } else {
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75)) {
                copies[index].drag = .zero
            }
        }
    }

    private func insert(_ copy: Copy, at index: Int, reduceMotion: Bool) {
        if let existing = copies.firstIndex(where: { $0.id == copy.id }) {
            // Undone while it was still leaving: call it back.
            withAnimation(DMMotion.spring.animation(reduceMotion: reduceMotion)) {
                copies[existing].leaving = nil
                copies[existing].drag = .zero
            }
        } else {
            var copy = copy
            copy.leaving = nil
            copy.drag = .zero
            // A deliberate snap: a little bounce as the copy lands on the stack.
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.62)) {
                copies.insert(copy, at: min(index, copies.count))
            }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 230))
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        let id = copy.id
        undoManager?.registerUndo(withTarget: self) { stack in
            stack.remove(id, .gather, reduceMotion: DMMotion.reduceMotion)
        }
    }

    private func remove(_ id: UUID, _ leaving: Copy.Leaving, reduceMotion: Bool) {
        guard let index = copies.firstIndex(where: { $0.id == id && $0.leaving == nil }) else { return }
        let original = copies[index]
        let position = copies[..<index].count { $0.leaving == nil }
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.2)
            : leaving == .gather ? .smooth(duration: 0.35)
            : .easeOut(duration: 0.4)
        copies[index].leavingSlot = position
        withAnimation(animation) {
            copies[index].leaving = leaving
        } completion: { [weak self] in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self?.copies.removeAll { $0.id == id && $0.leaving != nil }
            }
        }
        undoManager?.registerUndo(withTarget: self) { stack in
            stack.insert(original, at: index, reduceMotion: DMMotion.reduceMotion)
        }
    }

    func forgetUndo() {
        undoManager?.removeAllActions(withTarget: self)
    }
}

// MARK: - A copy on the stack

/// One copy at its slot in the fan, with the pose it peels off the mark from.
private struct CopyTile: View {
    let copy: CopyStack.Copy
    let slot: Int
    let reduceMotion: Bool
    let increasedContrast: Bool
    let onGather: () -> Void
    let onDrag: (CGSize) -> Void
    let onRelease: (CGSize, CGSize) -> Void

    static let size: CGFloat = 48

    /// The fan: each copy a little up, right and turned from the one below.
    private var slotCenter: CGPoint {
        CGPoint(x: 266 + CGFloat(slot) * 8, y: 74 - CGFloat(slot) * 5)
    }
    private var slotRotation: Double { -10 + Double(slot) * 6 }

    /// Sitting on the mark at its size, unturned: where a copy peels off from
    /// and where a gathered one goes back to.
    private var onMark: CopyPose {
        let mark = AboutSignature.markCenter
        return CopyPose(offset: CGSize(width: mark.x - slotCenter.x, height: mark.y - slotCenter.y),
                        scale: AboutSignature.markSize / Self.size, rotation: 0, opacity: 1)
    }

    private var pose: CopyPose {
        let resting = CopyPose(offset: copy.drag, scale: 1, rotation: slotRotation, opacity: 1)
        switch copy.leaving {
        case nil: return resting
        case .fade?: return CopyPose(offset: .zero, scale: reduceMotion ? 1 : 0.8, rotation: slotRotation, opacity: 0)
        case .gather?:
            if reduceMotion { return CopyPose(offset: .zero, scale: 1, rotation: slotRotation, opacity: 0) }
            var pose = onMark
            pose.opacity = 0
            return pose
        case .fling(let far)?:
            if reduceMotion { return CopyPose(offset: copy.drag, scale: 1, rotation: slotRotation, opacity: 0) }
            return CopyPose(offset: CGSize(width: copy.drag.width + far.width, height: copy.drag.height + far.height),
                            scale: 0.9, rotation: slotRotation + (far.width > 0 ? 40 : -40), opacity: 0)
        }
    }

    var body: some View {
        DittoMarkTile(size: Self.size)
            .overlay {
                if increasedContrast {
                    RoundedRectangle(cornerRadius: Self.size * 0.225, style: .continuous)
                        .strokeBorder(.primary.opacity(0.5), lineWidth: 1)
                }
            }
            .modifier(pose)
            .transition(.asymmetric(
                insertion: reduceMotion ? .opacity : .modifier(active: onMark, identity: pose),
                removal: .opacity))
            .contentShape(Rectangle())
            .onTapGesture(perform: onGather)
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { onDrag($0.translation) }
                    .onEnded { onRelease($0.translation, $0.predictedEndTranslation) }
            )
            .allowsHitTesting(copy.leaving == nil)
            .position(slotCenter)
    }
}

private struct CopyPose: ViewModifier, Equatable {
    var offset: CGSize
    var scale: CGFloat
    var rotation: Double
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .offset(offset)
            .opacity(opacity)
    }
}

#Preview {
    AboutSignature()
        .padding()
}
