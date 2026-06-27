import Foundation
import SwiftData

@Model final class KnownHostRecord {
    var id: UUID
    var hostAddress: String
    var port: Int
    var keyType: String
    var fingerprintSHA256: String
    init(id: UUID = UUID(), hostAddress: String, port: Int, keyType: String, fingerprintSHA256: String) {
        self.id = id
        self.hostAddress = hostAddress
        self.port = port
        self.keyType = keyType
        self.fingerprintSHA256 = fingerprintSHA256
    }
}
