import Foundation
import SwiftData

@Model final class SSHKeyRecord {
    var id: UUID
    var label: String
    var keyType: String
    var publicKeyOpenSSH: String
    var hasPassphrase: Bool
    /// Made in the Secure Enclave: the private half can't leave this device.
    // Inline default keeps SwiftData lightweight migration happy.
    var isSecureEnclave: Bool = false
    init(id: UUID = UUID(), label: String, keyType: String, publicKeyOpenSSH: String, hasPassphrase: Bool = false,
         isSecureEnclave: Bool = false) {
        self.id = id
        self.label = label
        self.keyType = keyType
        self.publicKeyOpenSSH = publicKeyOpenSSH
        self.hasPassphrase = hasPassphrase
        self.isSecureEnclave = isSecureEnclave
    }
}
