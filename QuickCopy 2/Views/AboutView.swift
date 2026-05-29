//
//  AboutView.swift
//  QuickCopy 2 (Ditto)
//
//  A custom About window, opened from Ditto → About Ditto.
//

import SwiftUI
import AppKit

struct AboutView: View {
    private var appIcon: NSImage { NSApp.applicationIconImage }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) (\(build))"
    }

    private var copyright: String {
        let year = Calendar.current.component(.year, from: .now)
        return "© \(year) Daniel McCullum"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 96, height: 96)
                .padding(.top, 30)

            Text("Ditto")
                .font(.system(size: 30, weight: .bold))
                .padding(.top, 10)

            Text("Your snippets, a click away.")
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 12)

            Divider()
                .padding(.horizontal, 40)
                .padding(.top, 20)

            VStack(spacing: 6) {
                featureLine("doc.on.clipboard.fill", "A native macOS snippets manager")
                featureLine("menubar.arrow.up.rectangle", "Quick copy from the menu bar")
                featureLine("square.and.arrow.up.fill", "Share snippets with ditto:// links")
            }
            .padding(.top, 18)

            Spacer(minLength: 0)

            Text(copyright)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)
        }
        .frame(width: 360, height: 420)
    }

    private func featureLine(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 20)
            Text(text)
                .font(.callout)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 44)
    }
}

#Preview {
    AboutView()
}
