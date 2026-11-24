import SwiftUI
import QuickLook

/// QuickLook preview for a file URL already staged on disk.
struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        return c
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

/// Reads a file through the engine, stages it on disk, and QuickLooks it.
/// Handles images, PDFs, Office docs, audio and video in one path.
struct PreviewSheet: View {
    @EnvironmentObject var app: AppModel
    let item: FileItem
    @State private var stagedURL: URL?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let stagedURL {
                    QuickLookView(url: stagedURL).ignoresSafeArea(edges: .bottom)
                } else if let error {
                    ContentUnavailableView("Can't Preview", systemImage: "eye.slash", description: Text(error))
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { stage() }
    }

    private func stage() {
        // If the real path is directly readable, preview it in place.
        if FileManager.default.isReadableFile(atPath: item.path) {
            stagedURL = item.url; return
        }
        do {
            let data = try app.fs.read(item.path)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(item.name)
            try? FileManager.default.removeItem(at: tmp)
            try data.write(to: tmp)
            stagedURL = tmp
        } catch {
            self.error = error.localizedDescription
        }
    }
}
