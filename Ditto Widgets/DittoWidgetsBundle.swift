//
//  DittoWidgetsBundle.swift
//  Ditto Widgets
//
//  Entry point of the widget extension, shared by the macOS (DittoWidgets)
//  and iOS (DittoiOSWidgets) targets. Each target also compiles its app's
//  Models, SnippetColor, and SharedStore so both read the same database.
//

import SwiftUI
import WidgetKit

@main
struct DittoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SnippetListWidget()
        SnippetButtonWidget()
        CopySnippetControl()
    }
}
