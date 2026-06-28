import SwiftUI

struct RemoteFileRow: View {
    let file: RemoteFile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(file.kind == .directory ? Color.accentColor : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).lineLimit(1)
                Text(subtitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if file.kind == .directory {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private var icon: String {
        switch file.kind {
        case .directory: return "folder.fill"
        case .symlink: return "arrowshape.turn.up.right"
        case .regular: return "doc"
        case .other: return "questionmark.square.dashed"
        }
    }

    private var subtitle: String {
        let perms = RemoteFile.permissionString(file.permissions)
        if file.kind == .directory { return perms }
        return "\(perms)  \(byteSize)"
    }

    private var byteSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)
    }
}
