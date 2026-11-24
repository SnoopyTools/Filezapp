import SwiftUI

struct PropertiesView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let item: FileItem

    @State private var attrs: FileAttributes?
    @State private var error: String?
    // Editable permission bits
    @State private var perms: [Bool] = Array(repeating: false, count: 9)
    @State private var permsLoaded = false

    private let labels = ["Owner R","Owner W","Owner X","Group R","Group W","Group X","Other R","Other W","Other X"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    row("Name", item.name)
                    row("Where", item.path.deletingLastPath)
                    row("Kind", kind)
                }
                if let a = attrs {
                    Section("Info") {
                        row("Size", Format.size(a.size))
                        row("Created", Format.date(a.created))
                        row("Modified", Format.date(a.modified))
                        if let target = a.symlinkTarget { row("Symlink →", target) }
                        if let rc = a.referenceCount { row("Links", "\(rc)") }
                    }
                    Section("Ownership") {
                        row("Owner", a.ownerName ?? a.ownerID.map(String.init) ?? "—")
                        row("Group", a.groupName ?? a.groupID.map(String.init) ?? "—")
                    }
                    Section {
                        ForEach(0..<9, id: \.self) { i in
                            Toggle(labels[i], isOn: $perms[i]).disabled(!permsLoaded)
                        }
                    } header: {
                        HStack { Text("Permissions"); Spacer()
                            Text("\(Format.permissions(mode))  (\(Format.octal(mode)))")
                                .font(.caption.monospaced()).foregroundStyle(.secondary) }
                    } footer: {
                        Text("Changing permissions outside the sandbox needs root.")
                    }
                } else if let error {
                    Section { Text(error).foregroundStyle(.red) }
                } else {
                    Section { ProgressView() }
                }
            }
            .navigationTitle("Properties")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { applyPermissions() }.disabled(!permsLoaded)
                }
            }
        }
        .task { load() }
    }

    private var kind: String {
        if item.isSymlink { return "Symbolic link" }
        if item.isDirectory { return "Folder" }
        return item.ext.isEmpty ? "File" : "\(item.ext.uppercased()) file"
    }

    private var mode: UInt16? {
        guard permsLoaded else { return attrs?.posixPermissions }
        var m: UInt16 = 0
        for (i, on) in perms.enumerated() where on { m |= UInt16(1 << (8 - i)) }
        return m
    }

    @ViewBuilder private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer()
            Text(v).multilineTextAlignment(.trailing).textSelection(.enabled) }
    }

    private func load() {
        do {
            let a = try app.fs.attributes(item.path)
            attrs = a
            if let p = a.posixPermissions {
                for i in 0..<9 { perms[i] = (Int(p) & (1 << (8 - i))) != 0 }
                permsLoaded = true
            }
        } catch { self.error = error.localizedDescription }
    }

    private func applyPermissions() {
        guard let m = mode else { return }
        do { try app.fs.setPosixPermissions(m, item.path) }
        catch { self.error = error.localizedDescription }
    }
}
