import Foundation

/// A raw directory entry handed back by a root backend.
struct RawEntry {
    let name: String
    let isDirectory: Bool
    let isSymlink: Bool
    let size: Int64
    let modified: Date?
}

// ─────────────────────────────────────────────────────────────────────────────
//  ROOT SEAM
//
//  Every privileged file operation in Filez goes through this one protocol —
//  and nothing else in the app knows how root is obtained. The shipped build
//  registers `UnavailableRootBackend`, so out of the box Filez runs entirely
//  inside its sandbox and never attempts anything it isn't allowed to.
//
//  To add root access later, WITHOUT changing any other file:
//    1. Create a new file, e.g. `MyRootBackend.swift`.
//    2. Make a type that conforms to `RootBackend`, implementing each primitive
//       with whatever mechanism you supply.
//    3. At launch, set:  RootBackendRegistry.active = MyRootBackend()
//
//  The whole UI already runs on top of this protocol, so the moment your
//  backend's `isAvailable` returns true, the full filesystem opens up.
// ─────────────────────────────────────────────────────────────────────────────
protocol RootBackend {
    var isAvailable: Bool { get }
    func list(_ path: String) throws -> [RawEntry]
    func attributes(_ path: String) throws -> FileAttributes
    func read(_ path: String) throws -> Data
    func write(_ data: Data, _ path: String) throws
    func createDirectory(_ path: String) throws
    func remove(_ path: String) throws
    func move(_ from: String, _ to: String) throws
    func setPosixPermissions(_ mode: UInt16, _ path: String) throws
}

enum RootBackendRegistry {
    // MARK: - ROOT HOOK — assign your own backend here. Default: none.
    static var active: RootBackend = UnavailableRootBackend()
}

/// Default backend: reports no root and refuses every privileged call.
struct UnavailableRootBackend: RootBackend {
    var isAvailable: Bool { false }
    func list(_ path: String) throws -> [RawEntry]                 { throw FileAccessError.rootUnavailable }
    func attributes(_ path: String) throws -> FileAttributes       { throw FileAccessError.rootUnavailable }
    func read(_ path: String) throws -> Data                       { throw FileAccessError.rootUnavailable }
    func write(_ data: Data, _ path: String) throws                { throw FileAccessError.rootUnavailable }
    func createDirectory(_ path: String) throws                    { throw FileAccessError.rootUnavailable }
    func remove(_ path: String) throws                             { throw FileAccessError.rootUnavailable }
    func move(_ from: String, _ to: String) throws                 { throw FileAccessError.rootUnavailable }
    func setPosixPermissions(_ mode: UInt16, _ path: String) throws { throw FileAccessError.rootUnavailable }
}

/// Adapts whatever backend is registered to the app's FileAccess interface.
struct RootFileAccess: FileAccess {
    var providesRootAccess: Bool { RootBackendRegistry.active.isAvailable }
    private var backend: RootBackend { RootBackendRegistry.active }

    func listDirectory(_ path: String) throws -> [FileItem] {
        try backend.list(path).map {
            FileItem(path: path.appendingPath($0.name), name: $0.name,
                     isDirectory: $0.isDirectory, isSymlink: $0.isSymlink,
                     size: $0.size, modified: $0.modified)
        }
    }
    func attributes(_ path: String) throws -> FileAttributes { try backend.attributes(path) }
    func read(_ path: String) throws -> Data { try backend.read(path) }
    func write(_ data: Data, to path: String) throws { try backend.write(data, path) }
    func createDirectory(_ path: String) throws { try backend.createDirectory(path) }
    func createFile(_ path: String, contents: Data) throws { try backend.write(contents, path) }
    func remove(_ path: String) throws { try backend.remove(path) }
    func move(_ from: String, to: String) throws { try backend.move(from, to) }
    func copy(_ from: String, to: String) throws {
        let data = try backend.read(from); try backend.write(data, to)
    }
    func setPosixPermissions(_ mode: UInt16, _ path: String) throws { try backend.setPosixPermissions(mode, path) }
}

/// Tries the sandbox first; on a permission wall, retries with root when present.
/// This is the engine the whole app actually uses.
struct CompositeFileAccess: FileAccess {
    private let sandbox = SandboxFileAccess()
    private let root = RootFileAccess()

    var providesRootAccess: Bool { root.providesRootAccess }

    private func attempt<T>(_ path: String, _ op: (FileAccess) throws -> T) throws -> T {
        do { return try op(sandbox) }
        catch FileAccessError.notPermitted {
            if root.providesRootAccess { return try op(root) }
            throw FileAccessError.notPermitted(path)
        }
    }

    func listDirectory(_ path: String) throws -> [FileItem] { try attempt(path) { try $0.listDirectory(path) } }
    func attributes(_ path: String) throws -> FileAttributes { try attempt(path) { try $0.attributes(path) } }
    func read(_ path: String) throws -> Data { try attempt(path) { try $0.read(path) } }
    func write(_ data: Data, to path: String) throws { try attempt(path) { try $0.write(data, to: path) } }
    func createDirectory(_ path: String) throws { try attempt(path) { try $0.createDirectory(path) } }
    func createFile(_ path: String, contents: Data) throws { try attempt(path) { try $0.createFile(path, contents: contents) } }
    func remove(_ path: String) throws { try attempt(path) { try $0.remove(path) } }
    func setPosixPermissions(_ mode: UInt16, _ path: String) throws { try attempt(path) { try $0.setPosixPermissions(mode, path) } }

    func move(_ from: String, to: String) throws {
        do { try sandbox.move(from, to: to) }
        catch FileAccessError.notPermitted {
            if root.providesRootAccess { try root.move(from, to: to) } else { throw FileAccessError.notPermitted(from) }
        }
    }
    func copy(_ from: String, to: String) throws {
        do { try sandbox.copy(from, to: to) }
        catch FileAccessError.notPermitted {
            if root.providesRootAccess { try root.copy(from, to: to) } else { throw FileAccessError.notPermitted(from) }
        }
    }
}
