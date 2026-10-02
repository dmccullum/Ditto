//
//  SettingsView.swift
//  DittoiOS
//
//  In-app settings, presented as a sheet from the library: library tools,
//  link preferences, a few tips, and the About bits.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Snippet.sortIndex) private var snippets: [Snippet]
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    @State private var exportDocument: DittoDocument?
    @State private var isImporting = false
    @State private var importMessage: String?
    @State private var markSpread: CGFloat = 0

    private var totalCopies: Int { snippets.reduce(0) { $0 + $1.copyCount } }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section { header }
                    .listRowBackground(Color.clear)

                Section("Library") {
                    NavigationLink {
                        ManageCategoriesView()
                    } label: {
                        LabeledContent {
                            Text("\(categories.count)").monospacedDigit()
                        } label: {
                            Label("Categories", systemImage: "folder")
                        }
                    }
                    Button {
                        exportDocument = (try? exportDitto(snippets: snippets, categories: categories))
                            .map(DittoDocument.init(data:))
                    } label: {
                        Label("Export Library…", systemImage: "square.and.arrow.up")
                    }
                    Button { isImporting = true } label: {
                        Label("Import Library…", systemImage: "square.and.arrow.down")
                    }
                }

                if UIDevice.current.userInterfaceIdiom == .phone {
                    Section("Layout") {
                        Picker(selection: $settings.railSide) {
                            ForEach(RailSide.allCases) { side in
                                Text(side.label).tag(side)
                            }
                        } label: {
                            Label("Rail Side", systemImage: "hand.raised")
                        }
                    }
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { settings.linkCategoryBehavior == .keep },
                        set: { settings.linkCategoryBehavior = $0 ? .keep : .uncategorized }
                    )) {
                        Label("Keep Categories", systemImage: "link")
                    }
                } header: {
                    Text("Shared Links")
                } footer: {
                    Text("When you open a ditto:// link, keep each snippet's original category. Turn this off to bring them in uncategorized.")
                }

                Section("Tips") {
                    tip("hand.tap.fill", .blue, "Tap a snippet to copy it.")
                    tip("hand.draw.fill", .orange, "Swipe right to pin. Swipe left to edit or delete.")
                    tip("hand.point.up.left.fill", .purple, "Touch and hold to preview the whole thing, share it, or duplicate it.")
                    tip("magnifyingglass", .indigo, "Search looks through every snippet, names first.")
                    tip("arrow.uturn.backward", .teal, "Deleted something by mistake? Shake to undo.")
                    tip("mic.fill", .pink, "Ask Siri to “Copy a Ditto snippet,” or put it on the Action button with Shortcuts.")
                }

                Section {
                    LabeledContent("Version", value: versionLine)
                } footer: {
                    Text("Made with love by Daniel McCullum")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                }
            }
            .fileExporter(
                isPresented: Binding(get: { exportDocument != nil },
                                     set: { if !$0 { exportDocument = nil } }),
                document: exportDocument,
                contentType: .json,
                defaultFilename: "Ditto Library \(Date.now.formatted(.dateTime.year().month().day()))"
            ) { _ in }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                importLibrary(result)
            }
            .alert("Import", isPresented: Binding(get: { importMessage != nil },
                                                  set: { if !$0 { importMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importMessage ?? "")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            DittoMarkTile(size: 76, spread: markSpread)
                .onTapGesture { replayMark() }
                .sensoryFeedback(.impact(flexibility: .soft), trigger: markSpread) { _, new in new == 1 }
            Text("Ditto")
                .font(.system(.title, design: .rounded, weight: .bold))
            Text(statLine)
                .font(.footnote.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(.tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(.tint.opacity(0.12)))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .onAppear { replayMark() }
    }

    /// A little bragging right: the app counts every copy, so say so.
    private var statLine: String {
        switch totalCopies {
        case 0:  return snippets.count == 1 ? "1 snippet, ready to go" : "\(snippets.count) snippets, ready to go"
        case 1:  return "1 copy and counting"
        default: return "\(totalCopies.formatted()) copies and counting"
        }
    }

    private func replayMark() {
        markSpread = 0
        withAnimation(.spring(response: 0.6, dampingFraction: 0.55).delay(0.15)) {
            markSpread = 1
        }
    }

    private func tip(_ symbol: String, _ tint: Color, _ text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
        }
    }

    private func importLibrary(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let before = snippets.count
            try importDitto(data: data, into: modelContext)
            let added = ((try? modelContext.fetchCount(FetchDescriptor<Snippet>())) ?? before) - before
            importMessage = switch added {
            case 0:  "Everything in that file is already in your library."
            case 1:  "Added 1 snippet."
            default: "Added \(added) snippets."
            }
        } catch {
            importMessage = "That file couldn't be imported. \(error.localizedDescription)"
        }
    }
}
