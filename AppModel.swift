import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    let fs: FileAccess = CompositeFileAccess()

    struct Clipboard { enum Mode { case copy, move }; let mode: Mode; let paths: [String] }
    @Published var clipboard: Clipboard?

    @Published var bookmarks: [String] {
        didSet { UserDefaults.standard.set(bookmarks, forKey: "bookmarks.v1") }
    }

    init() {
        bookmarks = UserDefaults.standard.stringArray(forKey: "bookmarks.v1") ?? []
    }

    var rootAvailable: Bool { fs.providesRootAccess }

    func toggleBookmark(_ path: String) {
        if let i = bookmarks.firstIndex(of: path) { bookmarks.remove(at: i) }
        else { bookmarks.append(path) }
    }
    func isBookmarked(_ path: String) -> Bool { bookmarks.contains(path) }

    // Unique destination path inside `dir` for an item named `name`.
    func uniquePath(in dir: String, name: String) -> String {
        var candidate = dir.appendingPath(name)
        guard (try? fs.attributes(candidate)) != nil else { return candidate }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        repeat {
            let newName = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            candidate = dir.appendingPath(newName)
            n += 1
        } while (try? fs.attributes(candidate)) != nil
        return candidate
    }

    func paste(into dir: String) throws {
        guard let clip = clipboard else { return }
        for src in clip.paths {
            let dest = uniquePath(in: dir, name: src.lastPath)
            switch clip.mode {
            case .copy: try fs.copy(src, to: dest)
            case .move: try fs.move(src, to: dest)
            }
        }
        clipboard = nil
    }
}

enum Format {
    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: date)
    }
    /// 0o755 -> "rwxr-xr-x"
    static func permissions(_ mode: UInt16?) -> String {
        guard let mode else { return "—" }
        let bits = ["---","--x","-w-","-wx","r--","r-x","rw-","rwx"]
        let o = Int(mode)
        return bits[(o >> 6) & 7] + bits[(o >> 3) & 7] + bits[o & 7]
    }
    static func octal(_ mode: UInt16?) -> String {
        guard let mode else { return "—" }
        return String(format: "%03o", Int(mode) & 0o777)
    }
}
