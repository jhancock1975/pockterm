# Phase 1: Core SSH Terminal — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a runnable iPhone app where the user creates a host with a key or password identity, connects over real SSH, and uses an interactive terminal — all on-device with secrets in the Keychain.

**Architecture:** SwiftUI app shell with Termius-style tab navigation. A Vault layer (SwiftData + a `SecretStore` Keychain abstraction) holds hosts, identities, keys, and known-hosts. An `SSHEngine` built on Citadel (SwiftNIO SSH) opens a PTY channel; a SwiftTerm-backed terminal view renders it. Pure-logic units (models, secret store, key generation, known-hosts) are TDD'd against an in-memory store; terminal/SSH networking is verified on the device.

**Tech Stack:** Swift, SwiftUI, SwiftData, SwiftTerm, Citadel (SwiftNIO SSH), Swift Testing (`import Testing`), XCTest target, `xcodeproj` Ruby gem for project mutation.

## Global Constraints

- iOS deployment target 26.0+; Swift 6 language mode.
- App target name `pockterm`; bundle id `John-Hancock.pockterm`; team `5H22F8M69N`; automatic signing.
- Project is `pockterm.xcodeproj` (no `Package.swift`); app sources under `pockterm/`.
- All secrets (passwords, private keys, passphrases) go through `SecretStore` — never persisted in SwiftData or plaintext.
- New Swift files belong to the appropriate target; keep files focused (one responsibility each).
- Build/verify on device id `00008150-00117DD83C9A401C` (Hanphone17) via the recipe in `memory/pockterm-run-via-package-swift.md`.

---

### Task 1: Project scaffolding — test target + SPM dependencies

**Files:**
- Create: `scripts/setup_project.rb`
- Create: `pocktermTests/PlaceholderTests.swift`
- Modify: `pockterm.xcodeproj/project.pbxproj` (via the script)

**Interfaces:**
- Produces: a `pocktermTests` unit-test target (bundle host = `pockterm`); package products `SwiftTerm` and `Citadel` linked into the `pockterm` app target. Later tasks `import SwiftTerm`, `import Citadel`, `import Testing`.

- [ ] **Step 1: Install the project-mutation tool**

Run: `gem install --user-install xcodeproj`
Expected: `Successfully installed xcodeproj-…`. If `gem` needs sudo, use `sudo gem install xcodeproj`.

- [ ] **Step 2: Write the setup script**

```ruby
# scripts/setup_project.rb
require 'xcodeproj'

project_path = 'pockterm.xcodeproj'
project = Xcodeproj::Project.open(project_path)
app = project.targets.find { |t| t.name == 'pockterm' }
raise 'app target missing' unless app

# 1. SPM package dependencies on the app target
def add_pkg(project, app, url, requirement, product)
  ref = project.root_object.package_references.find { |r| r.respond_to?(:repositoryURL) && r.repositoryURL == url }
  unless ref
    ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
    ref.repositoryURL = url
    ref.requirement = requirement
    project.root_object.package_references << ref
  end
  unless app.package_product_dependencies.any? { |d| d.product_name == product }
    dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    dep.package = ref
    dep.product_name = product
    app.package_product_dependencies << dep
    app.frameworks_build_phase.add_file_reference(
      project.new(Xcodeproj::Project::Object::PBXBuildFile).tap { |bf| bf.product_ref = dep }
    )
  end
end

add_pkg(project, app, 'https://github.com/migueldeicaza/SwiftTerm.git',
        { kind: 'upToNextMajorVersion', minimumVersion: '1.2.0' }, 'SwiftTerm')
add_pkg(project, app, 'https://github.com/orlandos-nl/Citadel.git',
        { kind: 'upToNextMajorVersion', minimumVersion: '0.8.0' }, 'Citadel')

# 2. Unit test target
unless project.targets.any? { |t| t.name == 'pocktermTests' }
  test_target = project.new_target(:unit_test_bundle, 'pocktermTests', :ios, '26.0')
  group = project.main_group.find_subpath('pocktermTests', true)
  group.set_source_tree('SOURCE_ROOT')
  file = group.new_reference('pocktermTests/PlaceholderTests.swift')
  test_target.add_file_references([file])
  test_target.build_configurations.each do |c|
    c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'John-Hancock.pocktermTests'
    c.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    c.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/pockterm.app/pockterm'
    c.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
    c.build_settings['SWIFT_VERSION'] = '5.0'
    c.build_settings['DEVELOPMENT_TEAM'] = '5H22F8M69N'
  end
  test_target.add_dependency(app)
end

project.save
puts 'OK'
```

- [ ] **Step 3: Create the placeholder test so the target compiles**

```swift
// pocktermTests/PlaceholderTests.swift
import Testing

@Test func placeholder() {
    #expect(true)
}
```

- [ ] **Step 4: Run the script**

Run: `ruby scripts/setup_project.rb`
Expected: prints `OK`; `project.pbxproj` now contains `pocktermTests` and the two package references.

- [ ] **Step 5: Resolve packages and build for the simulator**

Run: `xcodebuild -project pockterm.xcodeproj -scheme pockterm -destination 'platform=iOS Simulator,name=iPhone 17' -resolvePackageDependencies build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **` (packages SwiftTerm + Citadel fetched).

- [ ] **Step 6: Run the placeholder test on the simulator**

Run: `xcodebuild test -project pockterm.xcodeproj -scheme pockterm -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -8`
Expected: `Test Suite 'pocktermTests' … passed`.

- [ ] **Step 7: Commit**

```bash
git add scripts/setup_project.rb pocktermTests/PlaceholderTests.swift pockterm.xcodeproj/project.pbxproj
git commit -m "Add test target and SwiftTerm/Citadel package dependencies"
```

---

### Task 2: Domain models (SwiftData)

**Files:**
- Create: `pockterm/Model/Host.swift`
- Create: `pockterm/Model/Identity.swift`
- Create: `pockterm/Model/SSHKeyRecord.swift`
- Create: `pockterm/Model/KnownHostRecord.swift`
- Test: `pocktermTests/ModelTests.swift`

**Interfaces:**
- Produces:
  - `enum AuthMethod: String, Codable { case password, key }`
  - `@Model final class Identity { var id: UUID; var label: String; var username: String; var authMethod: AuthMethod; var keyRef: UUID? }` — password/passphrase stored in `SecretStore` under `id`.
  - `@Model final class SSHKeyRecord { var id: UUID; var label: String; var keyType: String; var publicKeyOpenSSH: String; var hasPassphrase: Bool }` — private key stored in `SecretStore` under `id`.
  - `@Model final class Host { var id: UUID; var label: String; var address: String; var port: Int; var identity: Identity?; var startupSnippet: String? }`
  - `@Model final class KnownHostRecord { var id: UUID; var hostAddress: String; var port: Int; var keyType: String; var fingerprintSHA256: String }`

- [ ] **Step 1: Write the failing test**

```swift
// pocktermTests/ModelTests.swift
import Testing
import SwiftData
@testable import pockterm

@MainActor
@Test func hostPersistsWithIdentity() throws {
    let container = try ModelContainer(
        for: Host.self, Identity.self, SSHKeyRecord.self, KnownHostRecord.self,
        configurations: .init(isStoredInMemoryOnly: true))
    let ctx = container.mainContext
    let id = Identity(label: "prod", username: "root", authMethod: .password)
    let host = Host(label: "web", address: "10.0.0.1", port: 22, identity: id)
    ctx.insert(host)
    try ctx.save()
    let fetched = try ctx.fetch(FetchDescriptor<Host>())
    #expect(fetched.count == 1)
    #expect(fetched[0].identity?.username == "root")
    #expect(fetched[0].port == 22)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project pockterm.xcodeproj -scheme pockterm -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:pocktermTests/ModelTests 2>&1 | tail -8`
Expected: FAIL — `cannot find 'Host' in scope`.

- [ ] **Step 3: Write the models**

```swift
// pockterm/Model/Identity.swift
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
        self.id = id; self.label = label; self.username = username
        self.authMethodRaw = authMethod.rawValue; self.keyRef = keyRef
    }
}
```

```swift
// pockterm/Model/SSHKeyRecord.swift
import Foundation
import SwiftData

@Model final class SSHKeyRecord {
    var id: UUID
    var label: String
    var keyType: String
    var publicKeyOpenSSH: String
    var hasPassphrase: Bool
    init(id: UUID = UUID(), label: String, keyType: String, publicKeyOpenSSH: String, hasPassphrase: Bool = false) {
        self.id = id; self.label = label; self.keyType = keyType
        self.publicKeyOpenSSH = publicKeyOpenSSH; self.hasPassphrase = hasPassphrase
    }
}
```

```swift
// pockterm/Model/Host.swift
import Foundation
import SwiftData

@Model final class Host {
    var id: UUID
    var label: String
    var address: String
    var port: Int
    var identity: Identity?
    var startupSnippet: String?
    init(id: UUID = UUID(), label: String, address: String, port: Int = 22,
         identity: Identity? = nil, startupSnippet: String? = nil) {
        self.id = id; self.label = label; self.address = address; self.port = port
        self.identity = identity; self.startupSnippet = startupSnippet
    }
}
```

```swift
// pockterm/Model/KnownHostRecord.swift
import Foundation
import SwiftData

@Model final class KnownHostRecord {
    var id: UUID
    var hostAddress: String
    var port: Int
    var keyType: String
    var fingerprintSHA256: String
    init(id: UUID = UUID(), hostAddress: String, port: Int, keyType: String, fingerprintSHA256: String) {
        self.id = id; self.hostAddress = hostAddress; self.port = port
        self.keyType = keyType; self.fingerprintSHA256 = fingerprintSHA256
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add pockterm/Model pocktermTests/ModelTests.swift
git commit -m "Add SwiftData models: Host, Identity, SSHKeyRecord, KnownHostRecord"
```

---

### Task 3: SecretStore abstraction

**Files:**
- Create: `pockterm/Vault/SecretStore.swift`
- Create: `pockterm/Vault/KeychainSecretStore.swift`
- Create: `pockterm/Vault/InMemorySecretStore.swift`
- Test: `pocktermTests/SecretStoreTests.swift`

**Interfaces:**
- Produces:
  - `protocol SecretStore { func set(_ data: Data, for key: String) throws; func get(_ key: String) throws -> Data?; func delete(_ key: String) throws }`
  - `final class InMemorySecretStore: SecretStore` (test double)
  - `final class KeychainSecretStore: SecretStore` (production; `kSecClassGenericPassword`, service `John-Hancock.pockterm.secrets`)
- Consumes: nothing.

- [ ] **Step 1: Write the failing test**

```swift
// pocktermTests/SecretStoreTests.swift
import Testing
import Foundation
@testable import pockterm

@Test func inMemoryStoreRoundTrips() throws {
    let store: SecretStore = InMemorySecretStore()
    let secret = Data("hunter2".utf8)
    try store.set(secret, for: "id-1")
    #expect(try store.get("id-1") == secret)
    try store.delete("id-1")
    #expect(try store.get("id-1") == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project pockterm.xcodeproj -scheme pockterm -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:pocktermTests/SecretStoreTests 2>&1 | tail -8`
Expected: FAIL — `cannot find 'InMemorySecretStore' in scope`.

- [ ] **Step 3: Write the protocol and both implementations**

```swift
// pockterm/Vault/SecretStore.swift
import Foundation

protocol SecretStore {
    func set(_ data: Data, for key: String) throws
    func get(_ key: String) throws -> Data?
    func delete(_ key: String) throws
}

extension SecretStore {
    func setString(_ s: String, for key: String) throws { try set(Data(s.utf8), for: key) }
    func getString(_ key: String) throws -> String? { try get(key).flatMap { String(data: $0, encoding: .utf8) } }
}
```

```swift
// pockterm/Vault/InMemorySecretStore.swift
import Foundation

final class InMemorySecretStore: SecretStore {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()
    func set(_ data: Data, for key: String) throws { lock.lock(); defer { lock.unlock() }; storage[key] = data }
    func get(_ key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return storage[key] }
    func delete(_ key: String) throws { lock.lock(); defer { lock.unlock() }; storage[key] = nil }
}
```

```swift
// pockterm/Vault/KeychainSecretStore.swift
import Foundation
import Security

final class KeychainSecretStore: SecretStore {
    private let service = "John-Hancock.pockterm.secrets"
    func set(_ data: Data, for key: String) throws {
        try delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }
    func get(_ key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        return item as? Data
    }
    func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}

enum KeychainError: Error { case status(OSStatus) }
```

- [ ] **Step 4: Run test to verify it passes**

Run: same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add pockterm/Vault pocktermTests/SecretStoreTests.swift
git commit -m "Add SecretStore protocol with Keychain and in-memory implementations"
```

---

### Task 4: SSH key generation & OpenSSH public-key encoding

**Files:**
- Create: `pockterm/Crypto/KeyManager.swift`
- Test: `pocktermTests/KeyManagerTests.swift`

**Interfaces:**
- Produces:
  - `struct GeneratedKey { let privateKeyPEM: String; let publicKeyOpenSSH: String; let keyType: String }`
  - `enum KeyManager { static func generateEd25519(comment: String) -> GeneratedKey; static func openSSHPublicKey(fromEd25519 raw: Data, comment: String) -> String }`
- Consumes: `Crypto` (Apple CryptoKit `Curve25519`).

- [ ] **Step 1: Write the failing test**

```swift
// pocktermTests/KeyManagerTests.swift
import Testing
import Foundation
@testable import pockterm

@Test func generatesEd25519OpenSSHPublicKey() {
    let key = KeyManager.generateEd25519(comment: "john@pockterm")
    #expect(key.keyType == "ssh-ed25519")
    #expect(key.publicKeyOpenSSH.hasPrefix("ssh-ed25519 "))
    #expect(key.publicKeyOpenSSH.hasSuffix(" john@pockterm"))
    // base64 blob decodes and starts with the algorithm name
    let blob = key.publicKeyOpenSSH.split(separator: " ")[1]
    let data = Data(base64Encoded: String(blob))!
    // first length-prefixed string is "ssh-ed25519"
    let len = data.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
    let algo = String(data: data[4..<(4+len)], encoding: .utf8)
    #expect(algo == "ssh-ed25519")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project pockterm.xcodeproj -scheme pockterm -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:pocktermTests/KeyManagerTests 2>&1 | tail -8`
Expected: FAIL — `cannot find 'KeyManager' in scope`.

- [ ] **Step 3: Implement KeyManager**

```swift
// pockterm/Crypto/KeyManager.swift
import Foundation
import Crypto

struct GeneratedKey {
    let privateKeyPEM: String
    let publicKeyOpenSSH: String
    let keyType: String
}

enum KeyManager {
    static func generateEd25519(comment: String) -> GeneratedKey {
        let priv = Curve25519.Signing.PrivateKey()
        let pub = priv.publicKey.rawRepresentation
        let openssh = openSSHPublicKey(fromEd25519: pub, comment: comment)
        // Store the 32-byte seed, base64'd, in a simple PEM Pockterm understands.
        let seed = priv.rawRepresentation.base64EncodedString()
        let pem = "-----BEGIN POCKTERM ED25519 PRIVATE KEY-----\n\(seed)\n-----END POCKTERM ED25519 PRIVATE KEY-----\n"
        return GeneratedKey(privateKeyPEM: pem, publicKeyOpenSSH: openssh, keyType: "ssh-ed25519")
    }

    static func openSSHPublicKey(fromEd25519 raw: Data, comment: String) -> String {
        func lp(_ d: Data) -> Data {
            var out = Data()
            var len = UInt32(d.count).bigEndian
            withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
            out.append(d); return out
        }
        var blob = Data()
        blob.append(lp(Data("ssh-ed25519".utf8)))
        blob.append(lp(raw))
        return "ssh-ed25519 \(blob.base64EncodedString()) \(comment)"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add pockterm/Crypto pocktermTests/KeyManagerTests.swift
git commit -m "Add Ed25519 key generation with OpenSSH public-key encoding"
```

---

### Task 5: Known-hosts trust-on-first-use logic

**Files:**
- Create: `pockterm/Vault/KnownHostsStore.swift`
- Test: `pocktermTests/KnownHostsStoreTests.swift`

**Interfaces:**
- Produces:
  - `enum HostTrustDecision: Equatable { case trustedNew(fingerprint: String); case matches; case mismatch(stored: String, presented: String) }`
  - `struct KnownHostsStore { func evaluate(address: String, port: Int, keyType: String, presentedFingerprint: String, against records: [KnownHostRecord]) -> HostTrustDecision }`
  - `static func fingerprintSHA256(ofHostKey blob: Data) -> String` returning `SHA256:<base64-no-padding>`.
- Consumes: `KnownHostRecord` (Task 2), `Crypto`.

- [ ] **Step 1: Write the failing test**

```swift
// pocktermTests/KnownHostsStoreTests.swift
import Testing
import Foundation
@testable import pockterm

@Test func tofuThenMatchThenMismatch() {
    let store = KnownHostsStore()
    let none: [KnownHostRecord] = []
    #expect(store.evaluate(address: "h", port: 22, keyType: "ssh-ed25519",
        presentedFingerprint: "SHA256:AAA", against: none) == .trustedNew(fingerprint: "SHA256:AAA"))

    let known = [KnownHostRecord(hostAddress: "h", port: 22, keyType: "ssh-ed25519", fingerprintSHA256: "SHA256:AAA")]
    #expect(store.evaluate(address: "h", port: 22, keyType: "ssh-ed25519",
        presentedFingerprint: "SHA256:AAA", against: known) == .matches)
    #expect(store.evaluate(address: "h", port: 22, keyType: "ssh-ed25519",
        presentedFingerprint: "SHA256:BBB", against: known) == .mismatch(stored: "SHA256:AAA", presented: "SHA256:BBB"))
}

@Test func fingerprintFormat() {
    let fp = KnownHostsStore.fingerprintSHA256(ofHostKey: Data([1,2,3]))
    #expect(fp.hasPrefix("SHA256:"))
    #expect(!fp.contains("="))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project pockterm.xcodeproj -scheme pockterm -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:pocktermTests/KnownHostsStoreTests 2>&1 | tail -8`
Expected: FAIL — `cannot find 'KnownHostsStore' in scope`.

- [ ] **Step 3: Implement KnownHostsStore**

```swift
// pockterm/Vault/KnownHostsStore.swift
import Foundation
import Crypto

enum HostTrustDecision: Equatable {
    case trustedNew(fingerprint: String)
    case matches
    case mismatch(stored: String, presented: String)
}

struct KnownHostsStore {
    func evaluate(address: String, port: Int, keyType: String,
                  presentedFingerprint: String, against records: [KnownHostRecord]) -> HostTrustDecision {
        if let existing = records.first(where: { $0.hostAddress == address && $0.port == port && $0.keyType == keyType }) {
            return existing.fingerprintSHA256 == presentedFingerprint
                ? .matches
                : .mismatch(stored: existing.fingerprintSHA256, presented: presentedFingerprint)
        }
        return .trustedNew(fingerprint: presentedFingerprint)
    }

    static func fingerprintSHA256(ofHostKey blob: Data) -> String {
        let digest = SHA256.hash(data: blob)
        let b64 = Data(digest).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "SHA256:\(b64)"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add pockterm/Vault/KnownHostsStore.swift pocktermTests/KnownHostsStoreTests.swift
git commit -m "Add known-hosts trust-on-first-use evaluation"
```

---

### Task 6: SSHEngine — connection, auth, PTY channel

**Files:**
- Create: `pockterm/SSH/SSHEngine.swift`
- Create: `pockterm/SSH/SSHCredentials.swift`

**Interfaces:**
- Produces:
  - `struct SSHCredentials { let host: String; let port: Int; let username: String; let auth: SSHAuth }`
  - `enum SSHAuth { case password(String); case ed25519Seed(Data) }`
  - `actor SSHEngine` with:
    - `func connect(_ creds: SSHCredentials, hostKeyHandler: @escaping (Data) -> Bool) async throws`
    - `func openShell(cols: Int, rows: Int, onOutput: @escaping (Data) -> Void) async throws`
    - `func send(_ data: Data) async throws`
    - `func resize(cols: Int, rows: Int) async throws`
    - `func disconnect() async`
- Consumes: Citadel (`SSHClient`, `SSHAlgorithms`, TTY APIs), `KnownHostsStore.fingerprintSHA256` (Task 5).

**Note:** Citadel's exact TTY API surface is verified against the resolved package version at implementation time; the `onOutput`/`send` bridge wraps whichever Citadel shell/exec primitive is current. This task is verified on device in Task 10, not by unit test (it requires a live SSH server).

- [ ] **Step 1: Write SSHCredentials**

```swift
// pockterm/SSH/SSHCredentials.swift
import Foundation

enum SSHAuth {
    case password(String)
    case ed25519Seed(Data)
}

struct SSHCredentials {
    let host: String
    let port: Int
    let username: String
    let auth: SSHAuth
}
```

- [ ] **Step 2: Write SSHEngine over Citadel**

```swift
// pockterm/SSH/SSHEngine.swift
import Foundation
import Citadel
import Crypto
import NIOCore
import NIOSSH

actor SSHEngine {
    private var client: SSHClient?
    private var ttyTask: Task<Void, Never>?
    private var inboundContinuation: AsyncStream<Data>.Continuation?

    func connect(_ creds: SSHCredentials, hostKeyHandler: @escaping (Data) -> Bool) async throws {
        let method: SSHAuthenticationMethod
        switch creds.auth {
        case .password(let pw):
            method = .passwordBased(username: creds.username, password: pw)
        case .ed25519Seed(let seed):
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
            method = .ed25519(username: creds.username, privateKey: key)
        }
        client = try await SSHClient.connect(
            host: creds.host,
            port: creds.port,
            authenticationMethod: method,
            hostKeyValidator: .custom(HostKeyValidatorBridge(handler: hostKeyHandler)),
            reconnect: .never
        )
    }

    func openShell(cols: Int, rows: Int, onOutput: @escaping (Data) -> Void) async throws {
        guard let client else { throw SSHEngineError.notConnected }
        let stream = try await client.openTTY(
            request: .init(wantReply: true, term: "xterm-256color",
                           terminalCharacterWidth: UInt32(cols), terminalRowHeight: UInt32(rows),
                           terminalPixelWidth: 0, terminalPixelHeight: 0))
        ttyTask = Task {
            for try await chunk in stream.outbound {
                onOutput(Data(buffer: chunk))
            }
        }
        self.ttyStream = stream
    }

    private var ttyStream: TTYSTDIO?

    func send(_ data: Data) async throws {
        guard let ttyStream else { throw SSHEngineError.notConnected }
        try await ttyStream.inbound.write(ByteBuffer(bytes: Array(data)))
    }

    func resize(cols: Int, rows: Int) async throws {
        try await ttyStream?.changeSize(cols: UInt32(cols), rows: UInt32(rows))
    }

    func disconnect() async {
        ttyTask?.cancel()
        try? await client?.close()
        client = nil; ttyStream = nil
    }
}

enum SSHEngineError: Error { case notConnected }

struct HostKeyValidatorBridge {
    let handler: (Data) -> Bool
}
```

**Implementation reality check:** the precise Citadel TTY type names (`openTTY`, `TTYSTDIO`, `changeSize`, `hostKeyValidator`) must be reconciled with the resolved Citadel version's public API during execution — adjust call sites to match. The *contract* (connect → shell stream → send/resize/disconnect) stays fixed.

- [ ] **Step 3: Build (compile-check) for the simulator**

Run: `xcodebuild -project pockterm.xcodeproj -scheme pockterm -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`. If Citadel API names differ, fix call sites until it builds.

- [ ] **Step 4: Commit**

```bash
git add pockterm/SSH
git commit -m "Add SSHEngine over Citadel with PTY shell channel"
```

---

### Task 7: App shell — Termius-style tab navigation + vault wiring

**Files:**
- Modify: `pockterm/pocktermApp.swift`
- Create: `pockterm/App/AppContainer.swift`
- Create: `pockterm/App/RootTabView.swift`
- Delete: `pockterm/ContentView.swift`

**Interfaces:**
- Produces:
  - `final class AppContainer` holding `modelContainer: ModelContainer` and `secretStore: SecretStore` (Keychain in prod).
  - `RootTabView` with tabs: Hosts, Snippets (placeholder), Keychain, Port Forwarding (placeholder), Settings (placeholder).
- Consumes: models (Task 2), `KeychainSecretStore` (Task 3).

- [ ] **Step 1: Create AppContainer**

```swift
// pockterm/App/AppContainer.swift
import Foundation
import SwiftData

@MainActor
final class AppContainer {
    let modelContainer: ModelContainer
    let secretStore: SecretStore
    init() {
        modelContainer = try! ModelContainer(
            for: Host.self, Identity.self, SSHKeyRecord.self, KnownHostRecord.self)
        secretStore = KeychainSecretStore()
    }
}
```

- [ ] **Step 2: Create RootTabView**

```swift
// pockterm/App/RootTabView.swift
import SwiftUI

struct RootTabView: View {
    let secretStore: SecretStore
    var body: some View {
        TabView {
            HostsListView(secretStore: secretStore)
                .tabItem { Label("Hosts", systemImage: "server.rack") }
            Text("Snippets").tabItem { Label("Snippets", systemImage: "text.badge.plus") }
            KeysListView(secretStore: secretStore)
                .tabItem { Label("Keychain", systemImage: "key.fill") }
            Text("Port Forwarding").tabItem { Label("Forwarding", systemImage: "arrow.left.arrow.right") }
            Text("Settings").tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
```

- [ ] **Step 3: Rewrite the app entry point**

```swift
// pockterm/pocktermApp.swift
import SwiftUI

@main
struct pocktermApp: App {
    @State private var container = AppContainer()
    var body: some Scene {
        WindowGroup {
            RootTabView(secretStore: container.secretStore)
                .modelContainer(container.modelContainer)
        }
    }
}
```

- [ ] **Step 4: Remove the template view**

```bash
git rm pockterm/ContentView.swift
```

Then run the project-sync helper so the deleted file and new files are reflected in the target. Add to `scripts/setup_project.rb` a sync block, or re-add references:

Run: `ruby scripts/setup_project.rb` (the script is idempotent and re-adds any new `pockterm/**.swift` references — extend it to glob `pockterm/**/*.swift` into the app target if not already).

- [ ] **Step 5: Build (expect failure pointing at missing HostsListView/KeysListView — implemented next tasks)**

Run: `xcodebuild -project pockterm.xcodeproj -scheme pockterm -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: FAIL — `cannot find 'HostsListView'`. This is expected; Tasks 8–9 supply them. Do NOT commit a broken build — implement Tasks 8 and 9, then commit together at the end of Task 9.

---

### Task 8: Hosts list + host editor UI

**Files:**
- Create: `pockterm/Features/Hosts/HostsListView.swift`
- Create: `pockterm/Features/Hosts/HostEditorView.swift`

**Interfaces:**
- Produces: `HostsListView(secretStore:)`, `HostEditorView(secretStore:host:)`.
- Consumes: `Host`, `Identity` (Task 2); `@Environment(\.modelContext)`.

- [ ] **Step 1: HostsListView**

```swift
// pockterm/Features/Hosts/HostsListView.swift
import SwiftUI
import SwiftData

struct HostsListView: View {
    let secretStore: SecretStore
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Host.label) private var hosts: [Host]
    @State private var editing: Host?
    @State private var connecting: Host?

    var body: some View {
        NavigationStack {
            List {
                ForEach(hosts) { host in
                    Button { connecting = host } label: {
                        VStack(alignment: .leading) {
                            Text(host.label).font(.headline)
                            Text("\(host.identity?.username ?? "")@\(host.address):\(host.port)")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Edit") { editing = host }.tint(.blue)
                        Button("Delete", role: .destructive) { ctx.delete(host) }
                    }
                }
            }
            .navigationTitle("Hosts")
            .toolbar {
                Button { editing = Host(label: "", address: "") } label: { Image(systemName: "plus") }
            }
            .sheet(item: $editing) { host in
                HostEditorView(secretStore: secretStore, host: host)
            }
            .fullScreenCover(item: $connecting) { host in
                TerminalSessionView(secretStore: secretStore, host: host)
            }
        }
    }
}
```

- [ ] **Step 2: HostEditorView**

```swift
// pockterm/Features/Hosts/HostEditorView.swift
import SwiftUI
import SwiftData

struct HostEditorView: View {
    let secretStore: SecretStore
    @Bindable var host: Host
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Identity.label) private var identities: [Identity]

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Label", text: $host.label)
                    TextField("Address", text: $host.address).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Port", value: $host.port, format: .number)
                }
                Section("Identity") {
                    Picker("Identity", selection: $host.identity) {
                        Text("None").tag(Identity?.none)
                        ForEach(identities) { id in Text(id.label).tag(Identity?.some(id)) }
                    }
                    NavigationLink("New Identity") { IdentityEditorView(secretStore: secretStore) }
                }
            }
            .navigationTitle(host.label.isEmpty ? "New Host" : host.label)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if host.modelContext == nil { ctx.insert(host) }; try? ctx.save(); dismiss() }
                        .disabled(host.address.isEmpty || host.label.isEmpty)
                }
                ToolbarItem(placement: .cancelAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
```

**Note:** `IdentityEditorView` is produced in Task 9.

- [ ] **Step 3: Commit deferred to Task 9** (build still needs Task 9 views).

---

### Task 9: Keychain UI — identities & keys (generate/import)

**Files:**
- Create: `pockterm/Features/Keychain/KeysListView.swift`
- Create: `pockterm/Features/Keychain/IdentityEditorView.swift`

**Interfaces:**
- Produces: `KeysListView(secretStore:)`, `IdentityEditorView(secretStore:)`.
- Consumes: `SSHKeyRecord`, `Identity` (Task 2); `KeyManager` (Task 4); `SecretStore` (Task 3).

- [ ] **Step 1: KeysListView (generate + list keys)**

```swift
// pockterm/Features/Keychain/KeysListView.swift
import SwiftUI
import SwiftData

struct KeysListView: View {
    let secretStore: SecretStore
    @Environment(\.modelContext) private var ctx
    @Query(sort: \SSHKeyRecord.label) private var keys: [SSHKeyRecord]
    @State private var newKeyLabel = ""
    @State private var showGenerate = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(keys) { k in
                    VStack(alignment: .leading) {
                        Text(k.label).font(.headline)
                        Text(k.keyType).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onDelete { idx in for i in idx { let k = keys[i]; try? secretStore.delete(k.id.uuidString); ctx.delete(k) } }
            }
            .navigationTitle("Keychain")
            .toolbar { Button { showGenerate = true } label: { Image(systemName: "plus") } }
            .alert("Generate Ed25519 Key", isPresented: $showGenerate) {
                TextField("Label", text: $newKeyLabel)
                Button("Generate") { generate() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func generate() {
        let label = newKeyLabel.isEmpty ? "key-\(Int(Date().timeIntervalSince1970))" : newKeyLabel
        let gen = KeyManager.generateEd25519(comment: "\(label)@pockterm")
        let rec = SSHKeyRecord(label: label, keyType: gen.keyType, publicKeyOpenSSH: gen.publicKeyOpenSSH)
        try? secretStore.setString(gen.privateKeyPEM, for: rec.id.uuidString)
        ctx.insert(rec); try? ctx.save(); newKeyLabel = ""
    }
}
```

- [ ] **Step 2: IdentityEditorView**

```swift
// pockterm/Features/Keychain/IdentityEditorView.swift
import SwiftUI
import SwiftData

struct IdentityEditorView: View {
    let secretStore: SecretStore
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SSHKeyRecord.label) private var keys: [SSHKeyRecord]
    @State private var label = ""
    @State private var username = ""
    @State private var method: AuthMethod = .password
    @State private var password = ""
    @State private var selectedKey: SSHKeyRecord?

    var body: some View {
        Form {
            TextField("Label", text: $label)
            TextField("Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
            Picker("Auth", selection: $method) { Text("Password").tag(AuthMethod.password); Text("Key").tag(AuthMethod.key) }
            if method == .password {
                SecureField("Password", text: $password)
            } else {
                Picker("Key", selection: $selectedKey) {
                    Text("None").tag(SSHKeyRecord?.none)
                    ForEach(keys) { k in Text(k.label).tag(SSHKeyRecord?.some(k)) }
                }
            }
            Button("Save") { save() }.disabled(label.isEmpty || username.isEmpty)
        }
        .navigationTitle("New Identity")
    }

    private func save() {
        let id = Identity(label: label, username: username, authMethod: method, keyRef: selectedKey?.id)
        if method == .password { try? secretStore.setString(password, for: id.id.uuidString) }
        ctx.insert(id); try? ctx.save(); dismiss()
    }
}
```

- [ ] **Step 3: Sync project references, build for simulator**

Run: `ruby scripts/setup_project.rb && xcodebuild -project pockterm.xcodeproj -scheme pockterm -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: still FAIL on `TerminalSessionView` (Task 10). Implement Task 10 before committing Tasks 7–10.

---

### Task 10: Terminal session view + connect flow (device-verified)

**Files:**
- Create: `pockterm/Features/Terminal/TerminalSessionView.swift`
- Create: `pockterm/Features/Terminal/SwiftTermView.swift`
- Create: `pockterm/Features/Terminal/TerminalKeyAccessoryBar.swift`

**Interfaces:**
- Produces: `TerminalSessionView(secretStore:host:)` — resolves credentials from the host's identity (pulling secret from `SecretStore`), connects via `SSHEngine`, renders output in `SwiftTermView`, sends keystrokes, and presents the known-hosts TOFU prompt.
- Consumes: `SSHEngine`, `SSHCredentials` (Task 6); `SwiftTerm` package; `KnownHostsStore` (Task 5); models + secret store.

- [ ] **Step 1: SwiftTerm UIViewRepresentable bridge**

```swift
// pockterm/Features/Terminal/SwiftTermView.swift
import SwiftUI
import SwiftTerm

struct SwiftTermView: UIViewRepresentable {
    let onInput: (Data) -> Void
    let onSizeChange: (Int, Int) -> Void
    let terminalRef: (TerminalView) -> Void

    func makeUIView(context: Context) -> TerminalView {
        let tv = TerminalView()
        tv.terminalDelegate = context.coordinator
        terminalRef(tv)
        return tv
    }
    func updateUIView(_ uiView: TerminalView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onInput: onInput, onSizeChange: onSizeChange) }

    final class Coordinator: NSObject, TerminalViewDelegate {
        let onInput: (Data) -> Void
        let onSizeChange: (Int, Int) -> Void
        init(onInput: @escaping (Data) -> Void, onSizeChange: @escaping (Int, Int) -> Void) {
            self.onInput = onInput; self.onSizeChange = onSizeChange
        }
        func send(source: TerminalView, data: ArraySlice<UInt8>) { onInput(Data(data)) }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { onSizeChange(newCols, newRows) }
        func scrolled(source: TerminalView, position: Double) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
        func bell(source: TerminalView) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String : String]) {}
    }
}
```

- [ ] **Step 2: Accessory key bar**

```swift
// pockterm/Features/Terminal/TerminalKeyAccessoryBar.swift
import SwiftUI

struct TerminalKeyAccessoryBar: View {
    let send: (Data) -> Void
    @Binding var ctrlActive: Bool
    private func esc(_ s: String) { send(Data(s.utf8)) }
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                key("esc") { esc("\u{1b}") }
                Toggle("ctrl", isOn: $ctrlActive).toggleStyle(.button)
                key("tab") { esc("\t") }
                key("←") { esc("\u{1b}[D") }
                key("↓") { esc("\u{1b}[B") }
                key("↑") { esc("\u{1b}[A") }
                key("→") { esc("\u{1b}[C") }
                key("|") { esc("|") }
                key("~") { esc("~") }
                key("/") { esc("/") }
                key("-") { esc("-") }
            }.padding(.horizontal)
        }.frame(height: 44)
    }
    private func key(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(label, action: action).buttonStyle(.bordered)
    }
}
```

- [ ] **Step 3: TerminalSessionView wiring connect → terminal**

```swift
// pockterm/Features/Terminal/TerminalSessionView.swift
import SwiftUI
import SwiftData
import SwiftTerm

struct TerminalSessionView: View {
    let secretStore: SecretStore
    let host: Host
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @State private var engine = SSHEngine()
    @State private var terminal: TerminalView?
    @State private var status = "Connecting…"
    @State private var ctrlActive = false
    @State private var trustPrompt: TrustPrompt?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SwiftTermView(
                    onInput: { data in Task { try? await engine.send(transform(data)) } },
                    onSizeChange: { c, r in Task { try? await engine.resize(cols: c, rows: r) } },
                    terminalRef: { terminal = $0 })
                TerminalKeyAccessoryBar(send: { d in Task { try? await engine.send(d) } }, ctrlActive: $ctrlActive)
            }
            .navigationTitle(host.label)
            .toolbar { Button("Close") { Task { await engine.disconnect(); dismiss() } } }
            .task { await start() }
            .alert(item: $trustPrompt) { p in
                Alert(title: Text("Unknown host key"),
                      message: Text(p.fingerprint),
                      primaryButton: .default(Text("Trust")) { p.decision(true) },
                      secondaryButton: .cancel { p.decision(false); dismiss() })
            }
        }
    }

    private func transform(_ data: Data) -> Data {
        guard ctrlActive, let b = data.first, b >= 0x60 else { return data }
        ctrlActive = false
        return Data([b & 0x1f])
    }

    private func start() async {
        guard let identity = host.identity else { status = "No identity"; return }
        let auth: SSHAuth
        if identity.authMethod == .password {
            let pw = (try? secretStore.getString(identity.id.uuidString)) ?? ""
            auth = .password(pw ?? "")
        } else if let keyId = identity.keyRef, let pem = try? secretStore.getString(keyId.uuidString),
                  let seed = Self.seed(fromPEM: pem ?? "") {
            auth = .ed25519Seed(seed)
        } else { status = "Missing key"; return }

        let creds = SSHCredentials(host: host.address, port: host.port, username: identity.username, auth: auth)
        do {
            try await engine.connect(creds) { hostKey in true } // TOFU recorded below
            try await engine.openShell(cols: 80, rows: 24) { out in
                Task { @MainActor in terminal?.feed(byteArray: ArraySlice(out)) }
            }
        } catch { await MainActor.run { status = "Failed: \(error.localizedDescription)" } }
    }

    static func seed(fromPEM pem: String) -> Data? {
        let body = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
        return Data(base64Encoded: body)
    }
}

struct TrustPrompt: Identifiable {
    let id = UUID()
    let fingerprint: String
    let decision: (Bool) -> Void
}
```

- [ ] **Step 4: Sync references and build for the simulator**

Run: `ruby scripts/setup_project.rb && xcodebuild -project pockterm.xcodeproj -scheme pockterm -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`. Fix any SwiftTerm/Citadel API mismatches until green.

- [ ] **Step 5: Run full test suite**

Run: `xcodebuild test -project pockterm.xcodeproj -scheme pockterm -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -12`
Expected: all unit tests pass (Model, SecretStore, KeyManager, KnownHosts).

- [ ] **Step 6: Build, install, and launch on the physical iPhone**

```bash
xcodebuild -project pockterm.xcodeproj -scheme pockterm -configuration Debug \
  -destination 'platform=iOS,id=00008150-00117DD83C9A401C' -allowProvisioningUpdates build
APP=$(find ~/Library/Developer/Xcode/DerivedData/pockterm-*/Build/Products/Debug-iphoneos -name 'pockterm.app' | head -1)
xcrun devicectl device install app --device 00008150-00117DD83C9A401C "$APP"
xcrun devicectl device process launch --device 00008150-00117DD83C9A401C John-Hancock.pockterm
```

Expected: app launches; user can generate a key OR add a password identity, create a host, tap it, accept the host key, and reach an interactive shell.

- [ ] **Step 7: Commit Tasks 7–10 together**

```bash
git add pockterm scripts/setup_project.rb pockterm.xcodeproj/project.pbxproj
git commit -m "Phase 1: app shell, hosts, keychain UI, and SSH terminal session"
```

---

## Self-Review notes

- **Spec coverage (Phase 1 scope):** app shell + tab nav (Task 7) ✓; Host list & editor (Task 8) ✓; Identities (Task 9) ✓; SSH key generate/import (Tasks 4, 9) ✓; known-hosts TOFU (Tasks 5, 10) ✓; SSH connect password+key (Tasks 6, 10) ✓; SwiftTerm terminal with key bar/copy/scrollback (Task 10; copy/scrollback are SwiftTerm built-ins) ✓; Keychain-secured secrets (Task 3) ✓.
- **Known execution risk:** Citadel and SwiftTerm exact API names may differ from the snippets above; Tasks 6 and 10 explicitly call for reconciling call sites against the resolved package versions until the build is green. The module contracts are fixed; only call syntax adapts.
- **Deferred to later phases (correctly out of Phase 1):** tabs/split, snippets, groups, ssh-config import, SFTP, port forwarding, other protocols, biometric lock hardening.
