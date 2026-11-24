import SwiftUI

private let textExts: Set<String> = [
    "txt","log","json","xml","strings","md","markdown","swift","c","h","m","mm","cpp","hpp",
    "sh","bash","zsh","conf","cfg","ini","yaml","yml","js","ts","css","html","htm","py","rb",
    "pl","php","go","rs","java","kt","gradle","toml","env","gitignore","entitlements","pbxproj"
]

enum SortKey: String, CaseIterable { case name = "Name", size = "Size", date = "Date", kind = "Kind" }

struct DirectoryView: View {
    @EnvironmentObject var app: AppModel
    let path: String

    @State private var items: [FileItem] = []
    @State private var loadError: String?
    @State private var search = ""
    @State private var sort: SortKey = .name
    @State private var ascending = true

    @State private var selectMode = false
    @State private var selected: Set<String> = []

    // Sheets
    @State private var properties: FileItem?
    @State private var textEdit: FileItem?
    @State private var hex: FileItem?
    @State private var plist: FileItem?
    @State private var preview: FileItem?

    // Dialogs
    @State private var renameItem: FileItem?
    @State private var renameText = ""
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var showNewFile = false
    @State private var newFileName = ""
    @State private var pendingDelete: [String] = []
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let loadError {
                Label(loadError, systemImage: "lock.slash").foregroundStyle(.secondary)
            }
            ForEach(filtered) { item in row(item) }
        }
        .listStyle(.plain)
        .navigationTitle(path == "/" ? "/" : path.lastPath)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search this folder")
        .refreshable { load() }
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) { if selectMode { selectionBar } }
        .task { load() }
        // Viewers
        .sheet(item: $properties) { PropertiesView(item: $0).environmentObject(app) }
        .sheet(item: $textEdit) { TextEditorSheet(item: $0).environmentObject(app) }
        .sheet(item: $hex) { HexView(item: $0).environmentObject(app) }
        .sheet(item: $plist) { PlistView(item: $0).environmentObject(app) }
        .sheet(item: $preview) { PreviewSheet(item: $0).environmentObject(app) }
        // Rename
        .alert("Rename", isPresented: Binding(get: { renameItem != nil }, set: { if !$0 { renameItem = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameItem = nil }
            Button("Rename") { performRename() }
        }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { performNewFolder() }
        }
        .alert("New File", isPresented: $showNewFile) {
            TextField("Name", text: $newFileName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { performNewFile() }
        }
        .confirmationDialog("Delete \(pendingDelete.count) item\(pendingDelete.count == 1 ? "" : "s")? This can't be undone.",
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: Rows

    @ViewBuilder private func row(_ item: FileItem) -> some View {
        if selectMode {
            Button { toggle(item) } label: { rowLabel(item, selectable: true) }
                .buttonStyle(.plain)
        } else if item.isDirectory {
            NavigationLink(value: item.path) { rowLabel(item) }
                .contextMenu { menu(item) }
                .swipeActions { swipe(item) }
        } else {
            Button { open(item) } label: { rowLabel(item) }
                .buttonStyle(.plain)
                .contextMenu { menu(item) }
                .swipeActions { swipe(item) }
        }
    }

    @ViewBuilder private func rowLabel(_ item: FileItem, selectable: Bool = false) -> some View {
        HStack(spacing: 12) {
            if selectable {
                Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected.contains(item.id) ? Color.accentColor : .secondary)
            }
            Image(systemName: icon(item))
                .foregroundStyle(item.isSymlink ? .orange : (item.isDirectory ? .accentColor : .secondary))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1)
                Text(subtitle(item)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if item.isDirectory && !selectable {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private func subtitle(_ item: FileItem) -> String {
        if item.isDirectory { return Format.date(item.modified) }
        return "\(Format.size(item.size)) · \(Format.date(item.modified))"
    }

    private func icon(_ item: FileItem) -> String {
        if item.isSymlink { return "arrow.triangle.turn.up.right.circle" }
        if item.isDirectory { return "folder.fill" }
        switch item.ext {
        case "plist": return "list.bullet.rectangle"
        case "zip","ipa","gz","tar","7z","rar": return "doc.zipper"
        case "png","jpg","jpeg","gif","heic","webp","bmp": return "photo"
        case "mp4","mov","m4v","mkv","avi": return "film"
        case "mp3","m4a","wav","aac","flac": return "music.note"
        case "pdf": return "doc.richtext"
        case "deb": return "shippingbox"
        default: return textExts.contains(item.ext) ? "doc.text" : "doc"
        }
    }

    // MARK: Context menu + swipe

    @ViewBuilder private func menu(_ item: FileItem) -> some View {
        if !item.isDirectory {
            Button { preview = item } label: { Label("Preview", systemImage: "eye") }
            Button { textEdit = item } label: { Label("Text Editor", systemImage: "doc.text") }
            Button { hex = item } label: { Label("Hex Viewer", systemImage: "number") }
            if item.ext == "plist" { Button { plist = item } label: { Label("Plist Editor", systemImage: "list.bullet.indent") } }
            if ArchiveService.extractable.contains(item.ext) {
                Button { extract(item) } label: { Label("Extract Here", systemImage: "arrow.up.bin") }
            }
        }
        Button { compress(item) } label: { Label("Compress to Zip", systemImage: "doc.zipper") }
        Divider()
        Button { startRename(item) } label: { Label("Rename", systemImage: "pencil") }
        Button { app.clipboard = .init(mode: .copy, paths: [item.path]) } label: { Label("Copy", systemImage: "doc.on.doc") }
        Button { app.clipboard = .init(mode: .move, paths: [item.path]) } label: { Label("Move", systemImage: "arrow.right.doc.on.clipboard") }
        Button { properties = item } label: { Label("Properties", systemImage: "info.circle") }
        if FileManager.default.isReadableFile(atPath: item.path) {
            ShareLink(item: item.url) { Label("Share", systemImage: "square.and.arrow.up") }
        }
        Divider()
        Button(role: .destructive) { pendingDelete = [item.path]; showDeleteConfirm = true } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder private func swipe(_ item: FileItem) -> some View {
        Button(role: .destructive) { pendingDelete = [item.path]; showDeleteConfirm = true } label: {
            Label("Delete", systemImage: "trash")
        }
        Button { startRename(item) } label: { Label("Rename", systemImage: "pencil") }.tint(.indigo)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(SortKey.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Button { ascending.toggle() } label: {
                    Label(ascending ? "Ascending" : "Descending",
                          systemImage: ascending ? "arrow.up" : "arrow.down")
                }
                Divider()
                Button { showNewFolder = true; newFolderName = "" } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                Button { showNewFile = true; newFileName = "" } label: { Label("New File", systemImage: "doc.badge.plus") }
                if app.clipboard != nil {
                    Button { pasteHere() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                }
                Divider()
                Button { app.toggleBookmark(path) } label: {
                    Label(app.isBookmarked(path) ? "Remove Bookmark" : "Bookmark Folder",
                          systemImage: app.isBookmarked(path) ? "bookmark.slash" : "bookmark")
                }
                Button { selectMode = true; selected = [] } label: { Label("Select", systemImage: "checkmark.circle") }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        if selectMode {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { selectMode = false; selected = [] }
            }
        }
    }

    private var selectionBar: some View {
        HStack {
            Button { app.clipboard = .init(mode: .copy, paths: Array(selected)); endSelect() } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }.disabled(selected.isEmpty)
            Spacer()
            Button { app.clipboard = .init(mode: .move, paths: Array(selected)); endSelect() } label: {
                Label("Move", systemImage: "arrow.right.doc.on.clipboard")
            }.disabled(selected.isEmpty)
            Spacer()
            Button { for p in selected { if let it = items.first(where: { $0.id == p }) { compress(it) } }; endSelect() } label: {
                Label("Zip", systemImage: "doc.zipper")
            }.disabled(selected.isEmpty)
            Spacer()
            Button(role: .destructive) { pendingDelete = Array(selected); showDeleteConfirm = true } label: {
                Label("Delete", systemImage: "trash")
            }.disabled(selected.isEmpty)
        }
        .labelStyle(.iconOnly).font(.title3)
        .padding(.horizontal).padding(.vertical, 10).background(.bar)
    }

    // MARK: Data

    private var filtered: [FileItem] {
        let base = search.isEmpty ? items
            : items.filter { $0.name.localizedCaseInsensitiveContains(search) }
        return base.sorted(by: order)
    }

    private func order(_ a: FileItem, _ b: FileItem) -> Bool {
        if a.isDirectory != b.isDirectory { return a.isDirectory }   // folders first
        let result: Bool
        switch sort {
        case .name: result = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        case .size: result = a.size < b.size
        case .date: result = (a.modified ?? .distantPast) < (b.modified ?? .distantPast)
        case .kind: result = a.ext.localizedCaseInsensitiveCompare(b.ext) == .orderedAscending
        }
        return ascending ? result : !result
    }

    private func load() {
        do { items = try app.fs.listDirectory(path); loadError = nil }
        catch { items = []; loadError = error.localizedDescription }
    }

    private func open(_ item: FileItem) {
        if textExts.contains(item.ext) { textEdit = item }
        else if item.ext == "plist" { plist = item }
        else { preview = item }
    }

    private func toggle(_ item: FileItem) {
        if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
    }
    private func endSelect() { selectMode = false; selected = [] }

    // MARK: Operations

    private func startRename(_ item: FileItem) { renameItem = item; renameText = item.name }

    private func performRename() {
        guard let item = renameItem else { return }
        let dest = path.appendingPath(renameText)
        do { try app.fs.move(item.path, to: dest); load() } catch { errorMessage = error.localizedDescription }
        renameItem = nil
    }

    private func performNewFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do { try app.fs.createDirectory(path.appendingPath(name)); load() } catch { errorMessage = error.localizedDescription }
    }

    private func performNewFile() {
        let name = newFileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do { try app.fs.createFile(path.appendingPath(name), contents: Data()); load() } catch { errorMessage = error.localizedDescription }
    }

    private func performDelete() {
        for p in pendingDelete {
            do { try app.fs.remove(p) } catch { errorMessage = error.localizedDescription }
        }
        pendingDelete = []; endSelect(); load()
    }

    private func pasteHere() {
        do { try app.paste(into: path); load() } catch { errorMessage = error.localizedDescription }
    }

    private func compress(_ item: FileItem) {
        do { try ArchiveService.compress(item.path, into: path, using: app.fs); load() }
        catch { errorMessage = error.localizedDescription }
    }

    private func extract(_ item: FileItem) {
        do { try ArchiveService.extract(item.path, into: path, using: app.fs); load() }
        catch { errorMessage = error.localizedDescription }
    }
}
