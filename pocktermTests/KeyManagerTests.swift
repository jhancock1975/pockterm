import Testing
import Foundation
import SwiftData
@testable import pockterm

@Test func generatesEd25519OpenSSHPublicKey() {
    let key = KeyManager.generateEd25519(comment: "john@pockterm")
    #expect(key.keyType == "ssh-ed25519")
    #expect(key.publicKeyOpenSSH.hasPrefix("ssh-ed25519 "))
    #expect(key.publicKeyOpenSSH.hasSuffix(" john@pockterm"))

    // The base64 blob decodes and its first length-prefixed string is the algorithm name.
    let blob = key.publicKeyOpenSSH.split(separator: " ")[1]
    let data = Data(base64Encoded: String(blob))!
    let len = data.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
    let algo = String(data: data[4..<(4 + len)], encoding: .utf8)
    #expect(algo == "ssh-ed25519")
}

@Test func privateKeyPEMRoundTripsToSeed() {
    let key = KeyManager.generateEd25519(comment: "c")
    let body = key.privateKeyPEM
        .split(separator: "\n")
        .filter { !$0.hasPrefix("-----") }
        .joined()
    let seed = Data(base64Encoded: body)
    #expect(seed?.count == 32)
}

// MARK: Importing a key the user already has

/// The fixtures are real `ssh-keygen` output, so they cannot live in the repo:
/// `scripts/routine-update`'s secret scan refuses a private key block in a
/// tracked file, and it is right to. Drop them into the app's Documents
/// directory and these tests run; otherwise they skip, the same way the
/// host-key integration test does when nothing is listening.
///
///     CONT=$(xcrun simctl get_app_container booted John-Hancock.pockterm data)
///     mkdir -p "$CONT/Documents/testkeys"
///     ssh-keygen -t ed25519 -f "$CONT/Documents/testkeys/ed_plain"  -N "" -q
///     ssh-keygen -t ed25519 -f "$CONT/Documents/testkeys/ed_locked" -N hunter2 -q
///     ssh-keygen -t rsa -b 2048 -f "$CONT/Documents/testkeys/rsa_plain" -N "" -q
///     ssh-keygen -t rsa -b 2048 -m PEM -f "$CONT/Documents/testkeys/rsa_legacy" -N "" -q
private func fixture(_ name: String) -> String? {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let text = try? String(contentsOf: documents.appending(path: "testkeys/\(name)"), encoding: .utf8)
    // Say so rather than passing silently: a skipped fixture test and a real
    // one look identical in the results, and these cover the only parsing we
    // do of somebody else's key material.
    print(text == nil ? "KEYFIXTURE missing \(name) — test skipped" : "KEYFIXTURE using \(name)")
    return text
}

/// `ssh-keygen`'s own public key line, reduced to algorithm and blob so the
/// comment (which the importer takes from the caller) does not matter.
private func algorithmAndBlob(_ openSSHLine: String) -> String {
    openSSHLine.split(separator: " ").prefix(2).joined(separator: " ")
}

@Test func importsAnUnencryptedEd25519Key() throws {
    guard let pem = fixture("ed_plain"), let expected = fixture("ed_plain.pub") else { return }
    let imported = try PrivateKeyImport.parse(pem, passphrase: nil, comment: "john@pockterm")

    #expect(imported.keyType == "ssh-ed25519")
    #expect(!imported.isEncrypted)
    // The public half has to match ssh-keygen's byte for byte, or the line the
    // user copies into authorized_keys will not be the key they imported.
    #expect(algorithmAndBlob(imported.publicKeyOpenSSH) == algorithmAndBlob(expected))
    #expect(imported.publicKeyOpenSSH.hasSuffix(" john@pockterm"))
}

@Test func importsAnUnencryptedRSAKey() throws {
    guard let pem = fixture("rsa_plain"), let expected = fixture("rsa_plain.pub") else { return }
    let imported = try PrivateKeyImport.parse(pem, passphrase: nil, comment: "john@pockterm")

    #expect(imported.keyType == "ssh-rsa")
    #expect(algorithmAndBlob(imported.publicKeyOpenSSH) == algorithmAndBlob(expected))
}

@Test func importsAPassphraseProtectedKey() throws {
    guard let pem = fixture("ed_locked"), let expected = fixture("ed_locked.pub") else { return }
    #expect(PrivateKeyImport.isEncrypted(pem))

    let imported = try PrivateKeyImport.parse(pem, passphrase: "hunter2", comment: "john@pockterm")
    #expect(imported.isEncrypted)
    #expect(algorithmAndBlob(imported.publicKeyOpenSSH) == algorithmAndBlob(expected))
}

/// Asking for the passphrase is a different outcome from failing, because the
/// caller has to know to put a field on screen rather than show an error.
@Test func asksForAPassphraseBeforeTryingToParse() throws {
    guard let pem = fixture("ed_locked") else { return }
    #expect(throws: PrivateKeyImportError.needsPassphrase) {
        try PrivateKeyImport.parse(pem, passphrase: nil, comment: "c")
    }
    #expect(throws: PrivateKeyImportError.needsPassphrase) {
        try PrivateKeyImport.parse(pem, passphrase: "", comment: "c")
    }
}

@Test func reportsAWrongPassphraseAsSuch() throws {
    guard let pem = fixture("ed_locked") else { return }
    #expect(throws: PrivateKeyImportError.wrongPassphrase) {
        try PrivateKeyImport.parse(pem, passphrase: "not-it", comment: "c")
    }
}

/// ssh-keygen wrote PKCS#1 by default before 7.8, so this is what a long-lived
/// id_rsa often still looks like. Citadel cannot read it, so the message has to
/// name the command that converts it rather than just refusing.
@Test func namesTheFixForLegacyPEMKeys() throws {
    guard let pem = fixture("rsa_legacy") else { return }
    #expect(throws: PrivateKeyImportError.legacyPEMFormat) {
        try PrivateKeyImport.parse(pem, passphrase: nil, comment: "c")
    }
}

@Test func refusesThingsThatAreNotKeys() {
    #expect(throws: PrivateKeyImportError.notAPrivateKey) {
        try PrivateKeyImport.parse("hello", passphrase: nil, comment: "c")
    }
    #expect(throws: PrivateKeyImportError.notAPrivateKey) {
        try PrivateKeyImport.parse("", passphrase: nil, comment: "c")
    }
    // A public key is the commonest wrong paste.
    #expect(throws: PrivateKeyImportError.notAPrivateKey) {
        try PrivateKeyImport.parse("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5 john@mac", passphrase: nil, comment: "c")
    }
}

// MARK: What an import actually persists

/// The container has to be held for the length of the test: a `ModelContext`
/// does not retain it, and letting it go resets the context.
@MainActor
private func withKeyContext(_ body: (ModelContext, InMemorySecretStore) throws -> Void) throws {
    let container = try ModelContainer(
        for: Host.self, Identity.self, SSHKeyRecord.self, KnownHostRecord.self,
        HostGroup.self, Snippet.self, CommandHistory.self,
        configurations: .init(isStoredInMemoryOnly: true))
    try body(container.mainContext, InMemorySecretStore())
}

@MainActor
@Test func importStoresTheKeyAndDescribesIt() throws {
    guard let pem = fixture("rsa_plain") else { return }
    try withKeyContext { ctx, store in
        let record = try PrivateKeyImport.store(pem, label: "work", passphrase: nil,
                                                into: store, context: ctx)

        #expect(record.label == "work")
        #expect(record.keyType == "ssh-rsa")
        #expect(!record.hasPassphrase)
        // The private half is kept exactly as pasted — the connection re-parses
        // this string, so anything reformatted here would fail to load later.
        let storedKey = try store.getString(record.id.uuidString)
        #expect(storedKey == pem.trimmingCharacters(in: .whitespacesAndNewlines))
        let storedPassphrase = try store.getString(PrivateKeyImport.passphraseKey(for: record.id))
        #expect(storedPassphrase == nil)
        let saved = try ctx.fetch(FetchDescriptor<SSHKeyRecord>())
        #expect(saved.count == 1)
    }
}

@MainActor
@Test func importKeepsThePassphraseWithTheKey() throws {
    guard let pem = fixture("ed_locked") else { return }
    try withKeyContext { ctx, store in
        let record = try PrivateKeyImport.store(pem, label: "locked", passphrase: "hunter2",
                                                into: store, context: ctx)

        #expect(record.hasPassphrase)
        let storedPassphrase = try store.getString(PrivateKeyImport.passphraseKey(for: record.id))
        #expect(storedPassphrase == "hunter2")
    }
}

/// A key that does not parse must leave nothing behind — a record with no
/// usable key under it would look like a working identity and fail at connect.
@MainActor
@Test func aFailedImportStoresNothing() throws {
    try withKeyContext { ctx, store in
        #expect(throws: PrivateKeyImportError.notAPrivateKey) {
            try PrivateKeyImport.store("nonsense", label: "bad", passphrase: nil,
                                       into: store, context: ctx)
        }
        let saved = try ctx.fetch(FetchDescriptor<SSHKeyRecord>())
        #expect(saved.isEmpty)
    }
}

/// An unlabelled import still gets a name, or the list shows a blank row.
@MainActor
@Test func importWithoutALabelGetsOne() throws {
    guard let pem = fixture("ed_plain") else { return }
    try withKeyContext { ctx, store in
        let record = try PrivateKeyImport.store(pem, label: "   ", passphrase: nil,
                                                into: store, context: ctx)
        #expect(record.label.hasPrefix("imported-"))
        #expect(record.publicKeyOpenSSH.hasSuffix("@pockterm"))
    }
}
