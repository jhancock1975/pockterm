import CommonCrypto
import Foundation

/// AES-128 in OCB mode (RFC 7253) with a 128-bit tag and a 96-bit nonce,
/// which is what the mosh protocol encrypts every datagram with.
///
/// Neither CryptoKit nor swift-crypto offers OCB, so it is built here from
/// raw AES block encryptions (CommonCrypto, ECB on single blocks). Written
/// from the RFC, and checked against its Appendix A vectors in the tests.
nonisolated final class AESOCB {
    static let tagLength = 16
    static let nonceLength = 12

    enum Failure: Error, Equatable {
        case badKey, badNonce, tooShort, authenticationFailed
    }

    private let encryptor: CCCryptorRef
    private let decryptor: CCCryptorRef
    private let lStar: Block
    private let lDollar: Block
    /// L_0, L_1, … ; L_i is needed for block numbers whose trailing-zero
    /// count is i, so 64 entries cover any message that fits in memory.
    private let l: [Block]

    init(key: Data) throws {
        guard key.count == kCCKeySizeAES128 else { throw Failure.badKey }
        func make(_ op: Int) throws -> CCCryptorRef {
            var ref: CCCryptorRef?
            let status = key.withUnsafeBytes {
                CCCryptorCreate(CCOperation(op), CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionECBMode), $0.baseAddress, key.count,
                                nil, &ref)
            }
            guard status == kCCSuccess, let ref else { throw Failure.badKey }
            return ref
        }
        encryptor = try make(kCCEncrypt)
        decryptor = try make(kCCDecrypt)

        var zero = Block()
        let star = Self.cipher(encryptor, &zero)
        lStar = star
        lDollar = star.doubled()
        var table = [lDollar.doubled()]
        for _ in 1..<64 { table.append(table[table.count - 1].doubled()) }
        l = table
    }

    deinit {
        CCCryptorRelease(encryptor)
        CCCryptorRelease(decryptor)
    }

    /// Ciphertext followed by the 16-byte tag.
    func seal(_ plaintext: Data, nonce: Data, associatedData: Data = Data()) throws -> Data {
        var offset = try initialOffset(nonce)
        var checksum = Block()
        var out = Data(capacity: plaintext.count + Self.tagLength)
        let full = plaintext.count / 16

        for i in 0..<full {
            offset ^= l[(i + 1).trailingZeroBitCount]
            let p = Block(plaintext, at: i * 16)
            checksum ^= p
            var x = p ^ offset
            out.append(contentsOf: (encipher(&x) ^ offset).bytes)
        }
        let rest = plaintext.count - full * 16
        if rest > 0 {
            offset ^= lStar
            var o = offset
            let pad = encipher(&o)
            var last = Block()
            for j in 0..<rest {
                let b = plaintext[plaintext.startIndex + full * 16 + j]
                out.append(b ^ pad[j])
                last[j] = b
            }
            last[rest] = 0x80
            checksum ^= last
        }
        var t = checksum ^ offset ^ lDollar
        let tag = encipher(&t) ^ hash(associatedData)
        out.append(contentsOf: tag.bytes)
        return out
    }

    /// Plaintext, or a throw if the tag doesn't match.
    func open(_ sealed: Data, nonce: Data, associatedData: Data = Data()) throws -> Data {
        guard sealed.count >= Self.tagLength else { throw Failure.tooShort }
        let length = sealed.count - Self.tagLength
        var offset = try initialOffset(nonce)
        var checksum = Block()
        var out = Data(capacity: length)
        let full = length / 16

        for i in 0..<full {
            offset ^= l[(i + 1).trailingZeroBitCount]
            var x = Block(sealed, at: i * 16) ^ offset
            let p = decipher(&x) ^ offset
            checksum ^= p
            out.append(contentsOf: p.bytes)
        }
        let rest = length - full * 16
        if rest > 0 {
            offset ^= lStar
            var o = offset
            let pad = encipher(&o)
            var last = Block()
            for j in 0..<rest {
                let b = sealed[sealed.startIndex + full * 16 + j] ^ pad[j]
                out.append(b)
                last[j] = b
            }
            last[rest] = 0x80
            checksum ^= last
        }
        var t = checksum ^ offset ^ lDollar
        let expected = encipher(&t) ^ hash(associatedData)
        let given = Block(sealed, at: length)
        // Constant-time compare.
        var diff: UInt8 = 0
        for j in 0..<16 { diff |= expected[j] ^ given[j] }
        guard diff == 0 else { throw Failure.authenticationFailed }
        return out
    }

    // MARK: - RFC 7253 pieces

    private func initialOffset(_ nonce: Data) throws -> Block {
        guard nonce.count == Self.nonceLength else { throw Failure.badNonce }
        // Nonce block: 7-bit tag length (128 mod 128 = 0), zero padding, a 1
        // bit, then the 96-bit nonce.
        var n = Block()
        n[3] = 0x01
        for j in 0..<12 { n[4 + j] = nonce[nonce.startIndex + j] }
        let bottom = Int(n[15] & 0x3F)
        n[15] &= 0xC0
        let top = encipher(&n)
        var stretch = [UInt8](repeating: 0, count: 24)
        for j in 0..<16 { stretch[j] = top[j] }
        for j in 0..<8 { stretch[16 + j] = top[j] ^ top[j + 1] }
        // Offset_0 is the 128 bits of Stretch starting at bit `bottom`.
        var offset = Block()
        let byteShift = bottom / 8, bitShift = bottom % 8
        for j in 0..<16 {
            let hi = stretch[j + byteShift]
            let lo = stretch[j + byteShift + 1]
            offset[j] = bitShift == 0 ? hi : (hi << bitShift) | (lo >> (8 - bitShift))
        }
        return offset
    }

    private func hash(_ a: Data) -> Block {
        var sum = Block()
        guard !a.isEmpty else { return sum }
        var offset = Block()
        let full = a.count / 16
        for i in 0..<full {
            offset ^= l[(i + 1).trailingZeroBitCount]
            var x = Block(a, at: i * 16) ^ offset
            sum ^= encipher(&x)
        }
        let rest = a.count - full * 16
        if rest > 0 {
            offset ^= lStar
            var last = Block()
            for j in 0..<rest { last[j] = a[a.startIndex + full * 16 + j] }
            last[rest] = 0x80
            var x = last ^ offset
            sum ^= encipher(&x)
        }
        return sum
    }

    private func encipher(_ b: inout Block) -> Block { Self.cipher(encryptor, &b) }
    private func decipher(_ b: inout Block) -> Block { Self.cipher(decryptor, &b) }

    private static func cipher(_ ref: CCCryptorRef, _ input: inout Block) -> Block {
        var output = Block()
        var moved = 0
        let status = withUnsafeBytes(of: &input.storage) { inp in
            withUnsafeMutableBytes(of: &output.storage) { outp in
                CCCryptorUpdate(ref, inp.baseAddress, 16, outp.baseAddress, 16, &moved)
            }
        }
        precondition(status == kCCSuccess && moved == 16, "AES block failed: \(status)")
        return output
    }
}

private typealias Block = OCBBlock

/// One 16-byte AES block, kept as two words so XOR is cheap.
nonisolated struct OCBBlock: Equatable {
    var storage: (UInt64, UInt64) = (0, 0)

    init() {}

    init(_ data: Data, at index: Int) {
        for j in 0..<16 { self[j] = data[data.startIndex + index + j] }
    }

    subscript(i: Int) -> UInt8 {
        get { withUnsafeBytes(of: storage) { $0[i] } }
        set { withUnsafeMutableBytes(of: &storage) { $0[i] = newValue } }
    }

    var bytes: [UInt8] { withUnsafeBytes(of: storage) { Array($0) } }

    /// Multiplication by x in GF(2^128), big-endian bit order.
    func doubled() -> OCBBlock {
        var r = OCBBlock()
        let carry = self[0] >> 7
        for j in 0..<15 { r[j] = (self[j] << 1) | (self[j + 1] >> 7) }
        r[15] = (self[15] << 1) ^ (carry == 1 ? 0x87 : 0)
        return r
    }

    static func ^ (a: OCBBlock, b: OCBBlock) -> OCBBlock {
        var r = OCBBlock()
        r.storage = (a.storage.0 ^ b.storage.0, a.storage.1 ^ b.storage.1)
        return r
    }

    static func ^= (a: inout OCBBlock, b: OCBBlock) { a = a ^ b }

    static func == (a: OCBBlock, b: OCBBlock) -> Bool {
        a.storage.0 == b.storage.0 && a.storage.1 == b.storage.1
    }
}
