import Foundation
import ZIPFoundation

/// Zip extract/compress that works regardless of the underlying engine.
/// Files are staged through a temp directory so root-located archives work too.
enum ArchiveService {
    static let extractable: Set<String> = ["zip", "ipa"]   // ipa is a zip

    /// Extracts `archivePath` into `destDir`, writing results back through `fs`.
    static func extract(_ archivePath: String, into destDir: String, using fs: FileAccess) throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("marrow-extract-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        // Stage the archive bytes to a real file, then unzip to a temp tree.
        let localZip = temp.appendingPathComponent("archive.zip")
        try fs.read(archivePath).write(to: localZip)
        let unpacked = temp.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: localZip, to: unpacked)

        // Name the output folder after the archive, uniquely.
        let folderName = (archivePath.lastPath as NSString).deletingPathExtension
        let outDir = uniqueDir(destDir, folderName.isEmpty ? "Extracted" : folderName, fs)
        try writeTreeBack(from: unpacked, toPath: outDir, using: fs)
    }

    /// Compresses `sourcePath` (file or folder) into `destDir` as `<name>.zip`.
    static func compress(_ sourcePath: String, into destDir: String, using fs: FileAccess) throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("marrow-zip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        // Stage the source into temp so ZIPFoundation has real files to read.
        let staged = temp.appendingPathComponent(sourcePath.lastPath)
        try stageToTemp(path: sourcePath, to: staged, using: fs)

        let zipURL = temp.appendingPathComponent("out.zip")
        try FileManager.default.zipItem(at: staged, to: zipURL, shouldKeepParent: true, compressionMethod: .deflate)

        let baseName = (sourcePath.lastPath as NSString).deletingPathExtension
        let dest = uniquePathForFile(destDir, (baseName.isEmpty ? "Archive" : baseName) + ".zip", fs)
        try fs.write(try Data(contentsOf: zipURL), to: dest)
    }

    // MARK: - Staging helpers

    private static func stageToTemp(path: String, to temp: URL, using fs: FileAccess) throws {
        let attrs = try fs.attributes(path)
        if attrs.isDirectory {
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            for child in try fs.listDirectory(path) {
                try stageToTemp(path: child.path, to: temp.appendingPathComponent(child.name), using: fs)
            }
        } else {
            try fs.read(path).write(to: temp)
        }
    }

    private static func writeTreeBack(from temp: URL, toPath path: String, using fs: FileAccess) throws {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: temp.path, isDirectory: &isDir)
        if isDir.boolValue {
            try fs.createDirectory(path)
            for child in try FileManager.default.contentsOfDirectory(atPath: temp.path) {
                try writeTreeBack(from: temp.appendingPathComponent(child),
                                  toPath: path.appendingPath(child), using: fs)
            }
        } else {
            try fs.write(try Data(contentsOf: temp), to: path)
        }
    }

    private static func uniqueDir(_ dir: String, _ name: String, _ fs: FileAccess) -> String {
        var candidate = dir.appendingPath(name); var n = 2
        while (try? fs.attributes(candidate)) != nil { candidate = dir.appendingPath("\(name) \(n)"); n += 1 }
        return candidate
    }
    private static func uniquePathForFile(_ dir: String, _ name: String, _ fs: FileAccess) -> String {
        var candidate = dir.appendingPath(name); var n = 2
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        while (try? fs.attributes(candidate)) != nil { candidate = dir.appendingPath("\(base) \(n).\(ext)"); n += 1 }
        return candidate
    }
}
