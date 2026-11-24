import Foundation

/// The always-present engine: plain FileManager, limited to whatever the
/// sandbox can legitimately reach. Restricted paths surface as `.notPermitted`,
/// which the composite engine uses to decide whether to fall back to root.
struct SandboxFileAccess: FileAccess {
    let providesRootAccess = false
    private let fm = FileManager.default

    func listDirectory(_ path: String) throws -> [FileItem] {
        let names: [String]
        do { names = try fm.contentsOfDirectory(atPath: path) }
        catch { throw FileAccessError.notPermitted(path) }
        return names.map { makeItem(path.appendingPath($0), name: $0) }
    }

    private func makeItem(_ full: String, name: String) -> FileItem {
        let attrs = try? fm.attributesOfItem(atPath: full)   // lstat: describes the link itself
        let type = attrs?[.type] as? FileAttributeType
        let isLink = type == .typeSymbolicLink
        var isDir = type == .typeDirectory
        if isLink {                                           // resolve link target for the folder chevron
            var dir: ObjCBool = false
            if fm.fileExists(atPath: full, isDirectory: &dir) { isDir = dir.boolValue }
        }
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let mod = attrs?[.modificationDate] as? Date
        return FileItem(path: full, name: name, isDirectory: isDir, isSymlink: isLink, size: size, modified: mod)
    }

    func attributes(_ path: String) throws -> FileAttributes {
        let a: [FileAttributeKey: Any]
        do { a = try fm.attributesOfItem(atPath: path) }
        catch { throw FileAccessError.notPermitted(path) }
        let type = a[.type] as? FileAttributeType
        var out = FileAttributes()
        out.size = (a[.size] as? NSNumber)?.int64Value ?? 0
        out.created = a[.creationDate] as? Date
        out.modified = a[.modificationDate] as? Date
        out.posixPermissions = (a[.posixPermissions] as? NSNumber)?.uint16Value
        out.ownerName = a[.ownerAccountName] as? String
        out.groupName = a[.groupOwnerAccountName] as? String
        out.ownerID = (a[.ownerAccountID] as? NSNumber)?.intValue
        out.groupID = (a[.groupOwnerAccountID] as? NSNumber)?.intValue
        out.referenceCount = (a[.referenceCount] as? NSNumber)?.intValue
        out.isDirectory = type == .typeDirectory
        out.isSymlink = type == .typeSymbolicLink
        out.symlinkTarget = try? fm.destinationOfSymbolicLink(atPath: path)
        return out
    }

    func read(_ path: String) throws -> Data {
        do { return try Data(contentsOf: URL(fileURLWithPath: path)) }
        catch { throw FileAccessError.notPermitted(path) }
    }

    func write(_ data: Data, to path: String) throws {
        do { try data.write(to: URL(fileURLWithPath: path)) }
        catch { throw FileAccessError.notPermitted(path) }
    }

    func createDirectory(_ path: String) throws {
        do { try fm.createDirectory(atPath: path, withIntermediateDirectories: true) }
        catch { throw FileAccessError.notPermitted(path) }
    }

    func createFile(_ path: String, contents: Data) throws {
        if !fm.createFile(atPath: path, contents: contents) { throw FileAccessError.notPermitted(path) }
    }

    func remove(_ path: String) throws {
        do { try fm.removeItem(atPath: path) }
        catch { throw FileAccessError.notPermitted(path) }
    }

    func move(_ from: String, to: String) throws {
        do { try fm.moveItem(atPath: from, toPath: to) }
        catch { throw FileAccessError.notPermitted(from) }
    }

    func copy(_ from: String, to: String) throws {
        do { try fm.copyItem(atPath: from, toPath: to) }
        catch { throw FileAccessError.notPermitted(from) }
    }

    func setPosixPermissions(_ mode: UInt16, _ path: String) throws {
        do { try fm.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: path) }
        catch { throw FileAccessError.notPermitted(path) }
    }
}
