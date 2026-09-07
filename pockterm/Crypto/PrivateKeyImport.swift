import Foundation
import SwiftData
import Citadel
import Crypto
import NIOSSH

/// What an imported key turned out to be. The private half is not carried here
/// — it stays in the text the user pasted, which goes to the Keychain.
struct ImportedPrivateKey {
    /// `ssh-ed25519` or `ssh-rsa`, matching `SSHKeyRecord.keyType`.
    let keyType: String
    let publicKeyOpenSSH: String
    let isEncrypted: Bool
}

/// Why an import was refused, worded for the person who pasted the key rather
/// than for the log.
enum PrivateKeyImportError: LocalizedError, Equatable {
    case notAPrivateKey
    case legacyPEMFormat
    case needsPassphrase
    case wrongPassphrase
    case unsupportedKeyType(String)
    case malformed

    var errorDescription: String? {
        switch self {
        case .notAPrivateKey:
            return String(localized: "That doesn't look like a private key. Paste the whole file, including the BEGIN and END lines.")
        case .legacyPEMFormat:
            // ssh-keygen wrote this format by default before 7.8, so plenty of
            // long-lived id_rsa files are still in it. Converting is one
            // command and does not change the key, so say which one.
            return String(localized: "This key is in the older PEM format. Convert it with `ssh-keygen -p -f <file>` — that rewrites the file in place without changing the key — then paste it again.")
        case .needsPassphrase:
            return String(localized: "This key is protected by a passphrase. Enter it to import the key.")
        case .wrongPassphrase:
            return String(localized: "That passphrase didn't unlock the key.")
        case .unsupportedKeyType(let type):
            return String(localized: "\(type) keys aren't supported yet. Ed25519 and RSA keys can be imported.")
        case .malformed:
            return String(localized: "The key could not be read. It may be incomplete or corrupted.")
        }
    }
}

/// Reads an OpenSSH private key the user already has, so a key does not have to
/// be generated in the app and added to every server by hand.
///
/// Only the OpenSSH container (`-----BEGIN OPENSSH PRIVATE KEY-----`) is read.
/// That is what `ssh-keygen` has written by default since 7.8, and it is the
/// only container Citadel can parse; the older PKCS#1 `BEGIN RSA PRIVATE KEY`
/// files get a message naming the one command that converts them, which is more
/// use than a parser we would have to write and maintain.
enum PrivateKeyImport {
    static let openSSHBegin = "-----BEGIN OPENSSH PRIVATE KEY-----"

    /// Where an imported key's passphrase lives in the Keychain, beside the key
    /// itself (which is stored under the key record's plain UUID).
    static func passphraseKey(for keyId: UUID) -> String {
        "\(keyId.uuidString)-passphrase"
    }

    /// Parses `text`, then records the key: the private half and any passphrase
    /// go to `store`, and an `SSHKeyRecord` describing it goes to `context`.
    /// Lives here rather than in the view so the part that decides what gets
    /// persisted can be tested without a screen.
    ///
    /// Nothing is written unless the key parses, so a failed import cannot
    /// leave a key record with no key behind it.
    @MainActor
    @discardableResult
    static func store(_ text: String,
                      label: String,
                      passphrase: String?,
                      into store: SecretStore,
                      context: ModelContext) throws -> SSHKeyRecord {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyLabel = name.isEmpty ? "imported-\(Int(Date().timeIntervalSince1970))" : name
        let imported = try parse(text, passphrase: passphrase, comment: "\(keyLabel)@pockterm")

        let record = SSHKeyRecord(label: keyLabel,
                                  keyType: imported.keyType,
                                  publicKeyOpenSSH: imported.publicKeyOpenSSH,
                                  hasPassphrase: imported.isEncrypted)
        // Stored exactly as pasted: this is the text the connection re-parses.
        try store.setString(text.trimmingCharacters(in: .whitespacesAndNewlines),
                            for: record.id.uuidString)
        if imported.isEncrypted, let passphrase {
            try store.setString(passphrase, for: passphraseKey(for: record.id))
        }
        context.insert(record)
        try? context.save()
        return record
    }

    /// Validates `text` and returns what it is. Throws
    /// `PrivateKeyImportError.needsPassphrase` when a passphrase is required
    /// and none was given, so the caller can ask for one and try again.
    static func parse(_ text: String, passphrase: String?, comment: String) throws -> ImportedPrivateKey {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix(openSSHBegin) else {
            throw key.contains("PRIVATE KEY-----") ? PrivateKeyImportError.legacyPEMFormat
                                                   : PrivateKeyImportError.notAPrivateKey
        }

        let encrypted = isEncrypted(key)
        let secret = passphrase.flatMap { $0.isEmpty ? nil : Data($0.utf8) }
        if encrypted && secret == nil { throw PrivateKeyImportError.needsPassphrase }

        let type: SSHKeyType
        do {
            type = try SSHKeyDetection.detectPrivateKeyType(from: key)
        } catch {
            throw PrivateKeyImportError.malformed
        }

        switch type {
        case .ed25519:
            let priv: Curve25519.Signing.PrivateKey
            do {
                priv = try Curve25519.Signing.PrivateKey(sshEd25519: key, decryptionKey: secret)
            } catch {
                throw failure(forEncrypted: encrypted)
            }
            return ImportedPrivateKey(
                keyType: "ssh-ed25519",
                publicKeyOpenSSH: KeyManager.openSSHPublicKey(
                    fromEd25519: priv.publicKey.rawRepresentation, comment: comment),
                isEncrypted: encrypted)

        case .rsa:
            let priv: Insecure.RSA.PrivateKey
            do {
                priv = try Insecure.RSA.PrivateKey(sshRsa: key, decryptionKey: secret)
            } catch {
                throw failure(forEncrypted: encrypted)
            }
            guard let pub = priv.publicKey as? Insecure.RSA.PublicKey else {
                throw PrivateKeyImportError.malformed
            }
            return ImportedPrivateKey(
                keyType: "ssh-rsa",
                publicKeyOpenSSH: openSSHPublicKey(fromRSA: pub, comment: comment),
                isEncrypted: encrypted)

        default:
            throw PrivateKeyImportError.unsupportedKeyType(type.description)
        }
    }

    /// A parse failure means a bad passphrase far more often than a damaged
    /// file, but only when there was a passphrase to get wrong.
    private static func failure(forEncrypted encrypted: Bool) -> PrivateKeyImportError {
        encrypted ? .wrongPassphrase : .malformed
    }

    /// Reads the cipher name out of the OpenSSH container. `none` means the key
    /// is stored in the clear. Anything unreadable is treated as not encrypted
    /// so the parse below produces the better error message.
    static func isEncrypted(_ key: String) -> Bool {
        let body = key
            .split(separator: "\n")
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let data = Data(base64Encoded: body) else { return false }
        let magic = Array("openssh-key-v1\0".utf8)
        guard data.count > magic.count + 4, data.starts(with: magic) else { return false }

        var index = data.startIndex + magic.count
        guard let length = readUInt32(data, at: &index),
              let cipher = readString(data, at: &index, length: length) else { return false }
        return cipher != "none"
    }

    private static func readUInt32(_ data: Data, at index: inout Data.Index) -> Int? {
        guard data.distance(from: index, to: data.endIndex) >= 4 else { return nil }
        var value: UInt32 = 0
        for _ in 0..<4 {
            value = value << 8 | UInt32(data[index])
            index = data.index(after: index)
        }
        return Int(value)
    }

    private static func readString(_ data: Data, at index: inout Data.Index, length: Int) -> String? {
        guard length >= 0, data.distance(from: index, to: data.endIndex) >= length else { return nil }
        let end = data.index(index, offsetBy: length)
        defer { index = end }
        return String(data: data[index..<end], encoding: .utf8)
    }

    /// `ssh-rsa` in `authorized_keys` form. `rawRepresentation` is already the
    /// wire body — mpint e followed by mpint n — so only the type string in
    /// front of it has to be added.
    static func openSSHPublicKey(fromRSA key: Insecure.RSA.PublicKey, comment: String) -> String {
        var blob = Data()
        var length = UInt32("ssh-rsa".utf8.count).bigEndian
        withUnsafeBytes(of: &length) { blob.append(contentsOf: $0) }
        blob.append(Data("ssh-rsa".utf8))
        blob.append(key.rawRepresentation)
        return "ssh-rsa \(blob.base64EncodedString()) \(comment)"
    }
}
