import Foundation
import SwiftData

enum AuthMethod: String, Codable { case password, key }

@Model final class Identity {
    var id: UUID
    var label: String
    var username: String
    var authMethodRaw: String
    var keyRef: UUID?
    var authMethod: AuthMethod {
        get { AuthMethod(rawValue: authMethodRaw) ?? .password }
        set { authMethodRaw = newValue.rawValue }
    }
    init(id: UUID = UUID(), label: String, username: String, authMethod: AuthMethod, keyRef: UUID? = nil) {
        self.id = id
        self.label = label
        self.username = username
        self.authMethodRaw = authMethod.rawValue
        self.keyRef = keyRef
    }
}
