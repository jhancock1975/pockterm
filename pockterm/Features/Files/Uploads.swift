import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// One file the user picked to upload.
struct UploadSource {
    let url: URL
    /// A copy made for the upload, deleted afterwards. Photo-library items
    /// arrive this way; Files-picker items are the user's own file.
    let isTemporary: Bool

    var name: String { url.lastPathComponent }
}

/// Position in a multi-file upload.
struct UploadBatch: Equatable {
    let position: Int
    let count: Int
}

/// What an upload put on the server, under the names it landed as.
struct UploadSummary: Equatable {
    let names: [String]
}

struct UploadFailure: Equatable, Identifiable {
    let id = UUID()
    let name: String
    let message: String
}

/// A photo or video from the library, copied to its own temporary folder so
/// it streams to the server like any other file and keeps its original name.
/// The picker is asked for the current encoding, so a HEIC stays a HEIC.
struct PickedMedia: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        // Movies first: a video must not be taken for its poster frame.
        FileRepresentation(importedContentType: .movie) { try PickedMedia(copying: $0.file) }
        FileRepresentation(importedContentType: .image) { try PickedMedia(copying: $0.file) }
    }

    /// The picker's file is only valid inside this call, hence the copy.
    init(copying source: URL) throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: url)
    }
}
