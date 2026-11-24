import SwiftUI

/// Recursively finds files of one category, from the sandbox (or the whole
/// filesystem when root is available). Bounded so it can't run away.
struct CategoryScanView: View {
    @EnvironmentObject var app: AppModel
    let category: FileCategory

    private let resultCap = 400
    private let depthCap = 7

    @State private var results: [FileItem] = []
    @State private var scanning = true
    @State private var cancelled = false

    @State private var preview: FileItem?
    @State private var textEdit: FileItem?
    @State private var hex: FileItem?
    @State private var plist: FileItem?

    var body: some View {
        List {
            ForEach(results) { item in
                Button { open(item) } label: { FileCell(item: item) }
                    .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .overlay {
            if results.isEmpty {
                if scanning { ProgressView("Scanning…") }
                else { ContentUnavailableView("Nothing Found",
                                              systemImage: category.kind.icon,
                                              description: Text("No \(category.title.lowercased()) in reach.")) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                if scanning { ProgressView().controlSize(.small) }
                Text("\(results.count) found\(results.count >= resultCap ? " (showing first \(resultCap))" : "")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal).padding(.vertical, 8).background(.bar)
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .blueBar()
        .task { await scan() }
        .onDisappear { cancelled = true }
        .sheet(item: $preview) { PreviewSheet(item: $0).environmentObject(app) }
        .sheet(item: $textEdit) { TextEditorSheet(item: $0).environmentObject(app) }
        .sheet(item: $hex) { HexView(item: $0).environmentObject(app) }
        .sheet(item: $plist) { PlistView(item: $0).environmentObject(app) }
    }

    private func open(_ item: FileItem) {
        let kind = FileKind.of(item)
        if kind.isTextLike { textEdit = item }
        else if kind == .plist { plist = item }
        else { preview = item }
    }

    private func scan() async {
        let roots = app.rootAvailable ? ["/"] : [NSHomeDirectory()]
        for root in roots {
            if cancelled || results.count >= resultCap { break }
            await walk(root, depth: 0)
        }
        scanning = false
    }

    private func walk(_ path: String, depth: Int) async {
        if cancelled || results.count >= resultCap || depth > depthCap { return }
        let entries = (try? app.fs.listDirectory(path)) ?? []
        for entry in entries {
            if cancelled || results.count >= resultCap { return }
            if entry.isDirectory {
                if !entry.isSymlink { await walk(entry.path, depth: depth + 1) }
            } else if category.exts.contains(entry.ext) {
                results.append(entry)
            }
        }
        await Task.yield()
    }
}
