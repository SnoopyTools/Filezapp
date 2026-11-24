import Foundation

/// One entry in a directory listing.
struct FileItem: Identifiable, Hashable {
    var id: String { path }
    let path: String            // absolute POSIX path
    let name: String
    let isDirectory: Bool
    let isSymlink: Bool
    let size: Int64
    let modified: Date?

    var url: URL { URL(fileURLWithPath: path) }
    var ext: String { (name as NSString).pathExtension.lowercased() }
}

struct FileAttributes {
    var size: Int64 = 0
    var created: Date?
    var modified: Date?
    var posixPermissions: UInt16?
    var ownerName: String?
    var groupName: String?
    var ownerID: Int?
    var groupID: Int?
    var isDirectory: Bool = false
    var isSymlink: Bool = false
    var symlinkTarget: String?
    var referenceCount: Int?
}

enum FileAccessError: LocalizedError {
    case notPermitted(String)
    case rootUnavailable
    case notFound(String)
    case generic(String)

    var errorDescription: String? {
        switch self {
        case .notPermitted(let p): return "Permission denied: \(p)"
        case .rootUnavailable:     return "Root access isn't available in this build."
        case .notFound(let p):     return "Not found: \(p)"
        case .generic(let m):      return m
        }
    }
}

/// Everything in the app reads and writes files ONLY through this interface.
/// That's what lets a root backend be dropped in later without touching the UI.
protocol FileAccess {
    /// True when this engine can reach outside the app sandbox.
    var providesRootAccess: Bool { get }

    func listDirectory(_ path: String) throws -> [FileItem]
    func attributes(_ path: String) throws -> FileAttributes
    func read(_ path: String) throws -> Data
    func write(_ data: Data, to path: String) throws
    func createDirectory(_ path: String) throws
    func createFile(_ path: String, contents: Data) throws
    func remove(_ path: String) throws
    func move(_ from: String, to: String) throws
    func copy(_ from: String, to: String) throws
    func setPosixPermissions(_ mode: UInt16, _ path: String) throws
}

extension String {
    /// Appends a path component POSIX-style.
    func appendingPath(_ component: String) -> String {
        (self as NSString).appendingPathComponent(component)
    }
    var lastPath: String { (self as NSString).lastPathComponent }
    var deletingLastPath: String { (self as NSString).deletingLastPathComponent }
}
