import SwiftUI

@main
struct FilezApp: App {
    @StateObject private var app = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(app)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        NavigationStack {
            LocationsView()
                .navigationDestination(for: String.self) { path in
                    DirectoryView(path: path)
                }
        }
    }
}

/// Start screen: standard locations plus the user's bookmarks.
struct LocationsView: View {
    @EnvironmentObject var app: AppModel

    private var standard: [(String, String, String)] {
        [
            ("App Sandbox", "house", NSHomeDirectory()),
            ("Documents",   "folder", NSHomeDirectory().appendingPath("Documents")),
            ("Temporary",   "clock", NSTemporaryDirectory()),
            ("Root  /",     "externaldrive", "/"),
            ("/var/mobile", "person.folder", "/var/mobile"),
        ]
    }

    var body: some View {
        List {
            Section("Locations") {
                ForEach(standard, id: \.2) { name, icon, path in
                    NavigationLink(value: path) {
                        Label(name, systemImage: icon)
                    }
                }
            }
            if !app.bookmarks.isEmpty {
                Section("Bookmarks") {
                    ForEach(app.bookmarks, id: \.self) { path in
                        NavigationLink(value: path) {
                            Label(path.lastPath, systemImage: "bookmark.fill")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .onDelete { idx in app.bookmarks.remove(atOffsets: idx) }
                }
            }
            Section {
                Label(app.rootAvailable ? "Root access: available" : "Root access: sandbox only",
                      systemImage: app.rootAvailable ? "checkmark.shield" : "lock.shield")
                    .foregroundStyle(app.rootAvailable ? .green : .secondary)
            } footer: {
                Text(app.rootAvailable
                     ? "The whole filesystem is reachable."
                     : "Folders outside the sandbox will show “Permission denied” until a root backend is added.")
            }
        }
        .navigationTitle("Filez")
    }
}
