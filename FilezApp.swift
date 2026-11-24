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
            HomeView()
                .navigationDestination(for: String.self) { DirectoryView(path: $0) }
                .navigationDestination(for: FileCategory.self) { CategoryScanView(category: $0) }
        }
        .tint(Theme.primary)
    }
}

struct LocationItem: Identifiable {
    var id: String { path }
    let name: String
    let path: String
}

/// ES-style home: storage banner, coloured category tiles, locations and bookmarks.
struct HomeView: View {
    @EnvironmentObject var app: AppModel

    private var locations: [LocationItem] {
        [
            .init(name: "App Sandbox", path: NSHomeDirectory()),
            .init(name: "Documents",   path: NSHomeDirectory().appendingPath("Documents")),
            .init(name: "Temporary",   path: NSTemporaryDirectory()),
            .init(name: "Root  /",     path: "/"),
            .init(name: "/var/mobile", path: "/var/mobile"),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StorageCard()

                sectionHeader("Categories")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                    ForEach(FileCategory.allCases) { cat in
                        NavigationLink(value: cat) { CategoryTile(category: cat) }
                            .buttonStyle(.plain)
                    }
                }

                sectionHeader("Local")
                card {
                    ForEach(Array(locations.enumerated()), id: \.element.id) { idx, loc in
                        NavigationLink(value: loc.path) {
                            locationRow(loc.name, icon: "folder.fill")
                        }
                        .buttonStyle(.plain)
                        if idx < locations.count - 1 { Divider().padding(.leading, 64) }
                    }
                }

                if !app.bookmarks.isEmpty {
                    sectionHeader("Bookmarks")
                    card {
                        ForEach(Array(app.bookmarks.enumerated()), id: \.element) { idx, path in
                            NavigationLink(value: path) {
                                locationRow(path.lastPath, icon: "bookmark.fill")
                            }
                            .buttonStyle(.plain)
                            if idx < app.bookmarks.count - 1 { Divider().padding(.leading, 64) }
                        }
                    }
                }

                rootStatus
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Filez")
        .blueBar()
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text).font(.headline).foregroundStyle(.secondary)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func locationRow(_ name: String, icon: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.primary.opacity(0.16))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: icon).foregroundStyle(Theme.primary))
            Text(name).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var rootStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: app.rootAvailable ? "checkmark.shield.fill" : "lock.shield.fill")
            Text(app.rootAvailable ? "Root access available — whole filesystem reachable"
                                   : "Sandbox only — folders outside the app show “Permission denied”")
                .font(.caption)
        }
        .foregroundStyle(app.rootAvailable ? Color.green : .secondary)
        .padding(.top, 4)
    }
}

struct CategoryTile: View {
    let category: FileCategory
    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(category.kind.color.opacity(0.16))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: category.kind.icon)
                        .font(.system(size: 23))
                        .foregroundStyle(category.kind.color)
                )
            Text(category.title).font(.caption).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}
