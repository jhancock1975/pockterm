import Foundation
import SwiftData

@Model final class SSHKeyRecord {
    var id: UUID
    var label: String
    var keyType: String
    var publicKeyOpenSSH: String
    var hasPassphrase: Bool
    init(id: UUID = UUID(), label: String, keyType: String, publicKeyOpenSSH: String, hasPassphrase: Bool = false) {
        self.id = id
        self.label = label
        self.keyType = keyType
        self.publicKeyOpenSSH = publicKeyOpenSSH
        self.hasPassphrase = hasPassphrase
    }
}
