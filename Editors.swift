import SwiftUI

private let maxEditBytes = 4 * 1024 * 1024   // 4 MB guard for in-memory editors

// MARK: - Text editor

struct TextEditorSheet: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let item: FileItem
    /// Optional override text (used by the plist "edit as XML" path).
    let initialText: String?
    /// Custom save handler; defaults to writing the string back to `item`.
    let onSave: ((String) -> Void)?

    init(item: FileItem, initialText: String? = nil, onSave: ((String) -> Void)? = nil) {
        self.item = item
        self.initialText = initialText
        self.onSave = onSave
    }

    @State private var text = ""
    @State private var loaded = false
    @State private var error: String?
    @State private var dirty = false

    var body: some View {
        NavigationStack {
            Group {
                if let error {
                    ContentUnavailableView("Can't Open", systemImage: "doc.text.magnifyingglass", description: Text(error))
                } else if loaded {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: text) { _, _ in dirty = true }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!loaded || !dirty || error != nil)
                }
            }
        }
        .task { load() }
    }

    private func load() {
        if let initialText { text = initialText; loaded = true; return }
        do {
            let data = try app.fs.read(item.path)
            guard data.count <= maxEditBytes else {
                error = "File is too large to edit as text (\(Format.size(Int64(data.count)))). Use the hex viewer."
                return
            }
            text = String(decoding: data, as: UTF8.self)
            loaded = true
        } catch { self.error = error.localizedDescription }
    }

    private func save() {
        if let onSave { onSave(text); dismiss(); return }
        do {
            try app.fs.write(Data(text.utf8), to: item.path)
            dirty = false
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Hex viewer (read-only in v1)

struct HexView: View {
    @EnvironmentObject var app: AppModel
    let item: FileItem
    @State private var lines: [String] = []
    @State private var error: String?
    @State private var truncated = false

    var body: some View {
        NavigationStack {
            Group {
                if let error {
                    ContentUnavailableView("Can't Open", systemImage: "number", description: Text(error))
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        Text(lines.joined(separator: "\n"))
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                    }
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if truncated {
                    Text("Showing the first 1 MB")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(6).background(.bar)
                }
            }
        }
        .task { load() }
    }

    private func load() {
        do {
            var data = try app.fs.read(item.path)
            let cap = 1024 * 1024
            if data.count > cap { data = data.prefix(cap); truncated = true }
            lines = Self.hexDump(data)
        } catch { self.error = error.localizedDescription }
    }

    static func hexDump(_ data: Data) -> [String] {
        var out: [String] = []
        var offset = 0
        let bytes = [UInt8](data)
        while offset < bytes.count {
            let chunk = bytes[offset..<min(offset + 16, bytes.count)]
            let hex = chunk.map { String(format: "%02x", $0) }.joined(separator: " ")
            let ascii = chunk.map { (32...126).contains($0) ? String(UnicodeScalar($0)) : "." }.joined()
            let padded = hex.padding(toLength: 47, withPad: " ", startingAt: 0)
            out.append(String(format: "%08x  %@  %@", offset, padded, ascii))
            offset += 16
        }
        return out
    }
}

// MARK: - Plist editor

struct PlistView: View {
    @EnvironmentObject var app: AppModel
    let item: FileItem
    @State private var root: PlistNode?
    @State private var error: String?
    @State private var editingXML = false
    @State private var xmlText = ""
    @State private var originalFormat: PropertyListSerialization.PropertyListFormat = .xml

    var body: some View {
        NavigationStack {
            Group {
                if let error {
                    ContentUnavailableView("Not a Property List", systemImage: "list.bullet.indent", description: Text(error))
                } else if let root {
                    List { PlistRow(node: root) }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit as XML") { prepareXML() }.disabled(root == nil)
                }
            }
        }
        .task { load() }
        .sheet(isPresented: $editingXML) {
            TextEditorSheet(item: item, initialText: xmlText, onSave: { edited in saveXML(edited) })
                .environmentObject(app)
        }
    }

    private func load() {
        do {
            let data = try app.fs.read(item.path)
            var fmt = PropertyListSerialization.PropertyListFormat.xml
            let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: &fmt)
            originalFormat = fmt
            root = PlistNode(key: item.name, value: obj)
        } catch { self.error = error.localizedDescription }
    }

    private func prepareXML() {
        guard let node = root else { return }
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: node.rawValue, format: .xml, options: 0)
            xmlText = String(decoding: data, as: UTF8.self)
            editingXML = true
        } catch { self.error = error.localizedDescription }
    }

    private func saveXML(_ xml: String) {
        do {
            var fmt = PropertyListSerialization.PropertyListFormat.xml
            let obj = try PropertyListSerialization.propertyList(from: Data(xml.utf8), options: [], format: &fmt)
            // Write back in the file's original format (binary stays binary).
            let data = try PropertyListSerialization.data(fromPropertyList: obj, format: originalFormat, options: 0)
            try app.fs.write(data, to: item.path)
            root = PlistNode(key: item.name, value: obj)
        } catch { self.error = error.localizedDescription }
    }
}

/// A node in a parsed property list, for the outline view.
final class PlistNode: Identifiable {
    let id = UUID()
    let key: String
    let rawValue: Any
    let children: [PlistNode]?
    let display: String

    init(key: String, value: Any) {
        self.key = key
        self.rawValue = value
        if let dict = value as? [String: Any] {
            children = dict.sorted { $0.key < $1.key }.map { PlistNode(key: $0.key, value: $0.value) }
            display = "{\(dict.count)}"
        } else if let arr = value as? [Any] {
            children = arr.enumerated().map { PlistNode(key: "[\($0.offset)]", value: $0.element) }
            display = "[\(arr.count)]"
        } else {
            children = nil
            if let d = value as? Data { display = "<\(d.count) bytes>" }
            else { display = "\(value)" }
        }
    }
}

struct PlistRow: View {
    let node: PlistNode
    var body: some View {
        if let children = node.children {
            DisclosureGroup {
                ForEach(children) { PlistRow(node: $0) }
            } label: {
                HStack { Text(node.key).fontWeight(.medium); Spacer(); Text(node.display).foregroundStyle(.secondary) }
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text(node.key).fontWeight(.medium)
                Spacer()
                Text(node.display).foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing).lineLimit(3)
            }
        }
    }
}
