//
//  WidgetSync.swift
//  Ditto
//
//  Redraws Ditto's widgets and controls after the app saves, so a renamed,
//  pinned, or deleted snippet shows up there without waiting for WidgetKit.
//

import Foundation
import SwiftData
import WidgetKit

@MainActor
enum WidgetSync {
    private static var observer: (any NSObjectProtocol)?
    private static var pendingReload: Task<Void, Never>?

    /// Start watching for saves. Called once by DittoStore.
    static func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { scheduleReload() }
        }
    }

    /// Typing in the editor saves in bursts; reload once they settle.
    private static func scheduleReload() {
        pendingReload?.cancel()
        pendingReload = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadAllTimelines()
            ControlCenter.shared.reloadAllControls()
        }
    }
}
