//
//  ShakeUndoBridge.swift
//  DittoiOS
//
//  iOS routes the shake / three-finger-swipe undo gestures to the first
//  responder's `undoManager`. With a plain SwiftUI + SwiftData app, no
//  responder vends the model context's undo manager, so the gestures do
//  nothing. This bridge inserts an invisible first-responder that returns the
//  context's undo manager, letting the system gestures undo data changes (and
//  show the native "Undo …" prompt). When a text field is focused it takes over
//  as first responder (text undo); this view reclaims it afterward.
//

import SwiftUI
import UIKit

struct ShakeUndoBridge: UIViewControllerRepresentable {
    var undoManager: UndoManager?

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.provider = { undoManager }
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.provider = { undoManager }
        // Reclaim first responder after an editor sheet dismisses, etc.
        if controller.viewIfLoaded?.window != nil, !controller.isFirstResponder {
            controller.becomeFirstResponder()
        }
    }

    final class Controller: UIViewController {
        var provider: (() -> UndoManager?)?

        override var undoManager: UndoManager? { provider?() }
        override var canBecomeFirstResponder: Bool { true }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            becomeFirstResponder()
        }
    }
}
