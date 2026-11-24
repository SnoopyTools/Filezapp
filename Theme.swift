import SwiftUI

enum Theme {
    static let primary     = Color(red: 0.13, green: 0.59, blue: 0.95)   // ~#2196F3
    static let primaryDark = Color(red: 0.09, green: 0.45, blue: 0.82)

    static var headerGradient: LinearGradient {
        LinearGradient(colors: [primary, primaryDark], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension View {
    /// ES-style coloured navigation bar.
    func blueBar() -> some View {
        self.toolbarBackground(Theme.primary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// MARK: - File kinds (icon + colour)

enum FileKind {
    case folder, image, video, audio, pdf, archive, code, plist, app, text, doc, link, other

    static func of(_ item: FileItem) -> FileKind {
        if item.isSymlink { return .link }
        if item.isDirectory { return .folder }
        switch item.ext {
        case "png","jpg","jpeg","gif","heic","heif","webp","bmp","tiff","svg": return .image
        case "mp4","mov","m4v","mkv","avi","webm","flv": return .video
        case "mp3","m4a","wav","aac","flac","ogg","opus": return .audio
        case "pdf": return .pdf
        case "zip","ipa","gz","tar","7z","rar","xz","bz2": return .archive
        case "plist": return .plist
        case "deb","app","dylib": return .app
        case "swift","c","h","m","mm","cpp","hpp","js","ts","py","rb","go","rs",
             "java","kt","sh","json","xml","yml","yaml","html","htm","css","php": return .code
        case "txt","log","md","markdown","rtf","strings","conf","cfg","ini": return .text
        case "doc","docx","pages","key","ppt","pptx","xls","xlsx","numbers","csv": return .doc
        default: return .other
        }
    }

    /// True when a plain tap should open the text editor.
    var isTextLike: Bool { self == .text || self == .code }

    var icon: String {
        switch self {
        case .folder:  return "folder.fill"
        case .image:   return "photo.fill"
        case .video:   return "film.fill"
        case .audio:   return "music.note"
        case .pdf:     return "doc.richtext.fill"
        case .archive: return "doc.zipper"
        case .code:    return "chevron.left.forwardslash.chevron.right"
        case .plist:   return "list.bullet.rectangle.fill"
        case .app:     return "shippingbox.fill"
        case .text:    return "doc.text.fill"
        case .doc:     return "doc.fill"
        case .link:    return "arrow.triangle.turn.up.right.circle.fill"
        case .other:   return "doc.fill"
        }
    }

    var color: Color {
        switch self {
        case .folder:  return Theme.primary
        case .image:   return Color(red: 0.30, green: 0.69, blue: 0.31)
        case .video:   return Color(red: 0.91, green: 0.30, blue: 0.40)
        case .audio:   return Color(red: 1.00, green: 0.60, blue: 0.00)
        case .pdf:     return Color(red: 0.90, green: 0.22, blue: 0.21)
        case .archive: return Color(red: 0.80, green: 0.52, blue: 0.25)
        case .code:    return Color(red: 0.40, green: 0.23, blue: 0.72)
        case .plist:   return Color(red: 0.61, green: 0.15, blue: 0.69)
        case .app:     return Color(red: 0.00, green: 0.59, blue: 0.53)
        case .text:    return Color(red: 0.33, green: 0.43, blue: 0.48)
        case .doc:     return Color(red: 0.10, green: 0.46, blue: 0.82)
        case .link:    return Color(red: 1.00, green: 0.60, blue: 0.00)
        case .other:   return Color.gray
        }
    }
}

struct IconBadge: View {
    let kind: FileKind
    var size: CGFloat = 40
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(kind.color.opacity(0.16))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: kind.icon)
                    .font(.system(size: size * 0.46))
                    .foregroundStyle(kind.color)
            )
    }
}

/// Shared list row used across the browser and category screens.
struct FileCell: View {
    let item: FileItem
    var body: some View {
        HStack(spacing: 12) {
            IconBadge(kind: .of(item))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if item.isDirectory {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
    private var subtitle: String {
        item.isDirectory ? Format.date(item.modified)
                         : "\(Format.size(item.size)) · \(Format.date(item.modified))"
    }
}

// MARK: - Categories (home-screen shortcuts)

enum FileCategory: String, CaseIterable, Identifiable, Hashable {
    case images, videos, audio, documents, archives, apps
    var id: String { rawValue }

    var title: String {
        switch self {
        case .images: return "Images"
        case .videos: return "Videos"
        case .audio: return "Audio"
        case .documents: return "Docs"
        case .archives: return "Archives"
        case .apps: return "Apps"
        }
    }

    var kind: FileKind {
        switch self {
        case .images: return .image
        case .videos: return .video
        case .audio: return .audio
        case .documents: return .doc
        case .archives: return .archive
        case .apps: return .app
        }
    }

    var exts: Set<String> {
        switch self {
        case .images: return ["png","jpg","jpeg","gif","heic","heif","webp","bmp","tiff","svg"]
        case .videos: return ["mp4","mov","m4v","mkv","avi","webm","flv"]
        case .audio: return ["mp3","m4a","wav","aac","flac","ogg","opus"]
        case .documents: return ["pdf","doc","docx","pages","key","ppt","pptx","xls","xlsx","numbers","csv","txt","md","rtf"]
        case .archives: return ["zip","ipa","gz","tar","7z","rar","xz","bz2"]
        case .apps: return ["ipa","deb","app","dylib"]
        }
    }
}

// MARK: - Storage

enum StorageInfo {
    static func capacity() -> (used: Int64, total: Int64)? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let vals = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ]), let total = vals.volumeTotalCapacity else { return nil }
        let free = vals.volumeAvailableCapacityForImportantUsage ?? 0
        return (Int64(total) - free, Int64(total))
    }
}

struct StorageCard: View {
    private let info = StorageInfo.capacity()
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "internaldrive.fill")
                Text("Device Storage").fontWeight(.semibold)
                Spacer()
                if let info { Text("\(Format.size(info.used)) of \(Format.size(info.total))").font(.caption) }
            }
            .foregroundStyle(.white)
            if let info, info.total > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25)).frame(height: 8)
                        Capsule().fill(.white)
                            .frame(width: geo.size.width * CGFloat(Double(info.used) / Double(info.total)), height: 8)
                    }
                }
                .frame(height: 8)
            }
        }
        .padding()
        .background(Theme.headerGradient)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
