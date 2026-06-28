import Foundation

enum SSHAuth {
    case password(String)
    /// Raw 32-byte Ed25519 seed (as produced by `KeyManager`).
    case ed25519Seed(Data)
}

struct SSHCredentials {
    let host: String
    let port: Int
    let username: String
    let auth: SSHAuth
}
