import Testing
import Foundation
@testable import pockterm

private func hex(_ s: String) -> Data {
    let chars = Array(s.filter { !$0.isWhitespace })
    return Data(stride(from: 0, to: chars.count, by: 2).map {
        UInt8(String(chars[$0...$0 + 1]), radix: 16)!
    })
}

private func num96(_ n: Int) -> Data {
    var d = Data(count: 4)
    d.appendBE(UInt64(n))
    return d
}

// RFC 7253 Appendix A, K = 000102…0F, 128-bit tag.
private let rfcKey = hex("000102030405060708090A0B0C0D0E0F")
private let rfcVectors: [(n: String, a: String, p: String, c: String)] = [
    ("BBAA99887766554433221100", "", "", "785407BFFFC8AD9EDCC5520AC9111EE6"),
    ("BBAA99887766554433221101", "0001020304050607", "0001020304050607",
     "6820B3657B6F615A5725BDA0D3B4EB3A257C9AF1F8F03009"),
    ("BBAA99887766554433221102", "0001020304050607", "",
     "81017F8203F081277152FADE694A0A00"),
    ("BBAA99887766554433221103", "", "0001020304050607",
     "45DD69F8F5AAE72414054CD1F35D82760B2CD00D2F99BFA9"),
    ("BBAA99887766554433221104", "000102030405060708090A0B0C0D0E0F",
     "000102030405060708090A0B0C0D0E0F",
     "571D535B60B277188BE5147170A9A22C3AD7A4FF3835B8C5701C1CCEC8FC3358"),
]

@Test func ocbMatchesTheRFCVectors() throws {
    let ocb = try AESOCB(key: rfcKey)
    for v in rfcVectors {
        let sealed = try ocb.seal(hex(v.p), nonce: hex(v.n), associatedData: hex(v.a))
        #expect(sealed == hex(v.c), "nonce \(v.n)")
        #expect(try ocb.open(sealed, nonce: hex(v.n), associatedData: hex(v.a)) == hex(v.p))
    }
}

/// RFC 7253's own all-lengths check: 128 messages of every length from 0
/// to 127 bytes, with and without associated data, folded into one tag.
@Test func ocbPassesTheRFCIterativeCheck() throws {
    var key = Data(count: 15); key.append(0x80)
    let ocb = try AESOCB(key: key)
    var c = Data()
    for i in 0..<128 {
        let s = Data(count: i)
        c.append(try ocb.seal(s, nonce: num96(3 * i + 1), associatedData: s))
        c.append(try ocb.seal(s, nonce: num96(3 * i + 2)))
        c.append(try ocb.seal(Data(), nonce: num96(3 * i + 3), associatedData: s))
        // Every one of those has to open again.
        let sealed = try ocb.seal(s, nonce: num96(3 * i + 2))
        #expect(try ocb.open(sealed, nonce: num96(3 * i + 2)) == s)
    }
    let tag = try ocb.seal(Data(), nonce: num96(385), associatedData: c)
    #expect(tag == hex("67E944D23256C5E0B6C61FA22FDF1EA2"))
}

@Test func ocbRejectsAnyTamperedByte() throws {
    let ocb = try AESOCB(key: rfcKey)
    let nonce = hex("BBAA99887766554433221104")
    let sealed = try ocb.seal(Data("hello, mosh server".utf8), nonce: nonce)
    for i in sealed.indices {
        var bad = sealed
        bad[i] ^= 0x01
        #expect(throws: AESOCB.Failure.authenticationFailed) { try ocb.open(bad, nonce: nonce) }
    }
    #expect(throws: AESOCB.Failure.badKey) { try AESOCB(key: Data(count: 15)) }
}

@Test func sessionKeyIsUnpaddedBase64() {
    #expect(MoshKey.decode("AAECAwQFBgcICQoLDA0ODw") == rfcKey)
    #expect(MoshKey.decode(" AAECAwQFBgcICQoLDA0ODw\n") == rfcKey)
    #expect(MoshKey.decode("AAECAwQFBgcICQoLDA0ODw==") == nil)
    #expect(MoshKey.decode("not a key") == nil)
}

@Test func packetsRoundTripAndCarryTheDirectionInTheNonce() throws {
    let cipher = try MoshCipher(key: rfcKey)
    let p = MoshPacket(sequence: 42, direction: .toClient, timestamp: 1234,
                       timestampReply: MoshPacket.noTimestamp, payload: Data("xyz".utf8))
    let datagram = try cipher.seal(p)
    #expect(datagram.count == 8 + 4 + 3 + 16)
    #expect(datagram.prefix(8) == hex("800000000000002A"))
    #expect(try cipher.open(datagram) == p)

    let up = MoshPacket(sequence: 7, direction: .toServer, timestamp: 0, timestampReply: 9,
                        payload: Data())
    let upGram = try cipher.seal(up)
    #expect(upGram.prefix(8) == hex("0000000000000007"))
    #expect(try cipher.open(upGram) == up)

    let other = try MoshCipher(key: Data(count: 16))
    #expect(throws: AESOCB.Failure.authenticationFailed) { try other.open(datagram) }
}

@Test func fragmentsSplitAndReassembleOutOfOrder() throws {
    let data = Data((0..<2500).map { UInt8($0 % 251) })
    let parts = MoshFragment.split(data, id: 9, maxContents: 1000)
    #expect(parts.map(\.contents.count) == [1000, 1000, 500])
    #expect(parts.map(\.isFinal) == [false, false, true])

    let wire = parts.map(\.encoded)
    #expect(wire[2].prefix(10) == hex("0000000000000009 8002"))

    var assembly = MoshFragmentAssembly()
    #expect(assembly.add(MoshFragment(wire[2])!) == nil)
    #expect(assembly.add(MoshFragment(wire[0])!) == nil)
    #expect(assembly.add(MoshFragment(wire[1])!) == data)

    // Empty data is still one (final) fragment.
    #expect(MoshFragment.split(Data(), id: 1, maxContents: 10).count == 1)
}

@Test func aNewerInstructionAbandonsAPartialOne() {
    var assembly = MoshFragmentAssembly()
    let old = MoshFragment.split(Data(count: 20), id: 1, maxContents: 10)
    let new = MoshFragment.split(Data([1, 2, 3]), id: 2, maxContents: 10)
    #expect(assembly.add(old[0]) == nil)
    #expect(assembly.add(new[0]) == Data([1, 2, 3]))
    #expect(assembly.add(old[1]) == nil)   // its first half is gone
}

@Test func zlibRoundTripsAndChecksItsTrailer() throws {
    let text = Data(String(repeating: "\u{1b}[H\u{1b}[2Jhello mosh ", count: 200).utf8)
    let z = try Zlib.compress(text)
    #expect(z.prefix(2) == Data([0x78, 0x9C]))
    #expect(z.count < text.count / 10)
    #expect(try Zlib.decompress(z) == text)
    #expect(try Zlib.decompress(try Zlib.compress(Data())) == Data())

    var bad = z
    bad[bad.count - 1] ^= 1
    #expect(throws: Zlib.Failure.badChecksum) { try Zlib.decompress(bad) }

    // A stream made by real zlib (Python's zlib.compress(b"hello")).
    #expect(try Zlib.decompress(hex("789CCB48CDC9C90700062C0215")) == Data("hello".utf8))
    #expect(Zlib.adler32(Data("Wikipedia".utf8)) == 0x11E60398)
}

@Test func instructionsRoundTripThroughProtobuf() throws {
    let i = MoshInstruction(oldNum: 3, newNum: 300, ackNum: 1 << 40, throwawayNum: 2,
                            diff: Data("d".utf8), chaff: Data([0, 1]))
    let bytes = i.encoded
    // protocol_version = 2 comes first, as field 1 varint.
    #expect(bytes.prefix(2) == Data([0x08, 0x02]))
    #expect(try MoshInstruction(bytes) == i)
    #expect(try MoshInstruction(Data()).protocolVersion == MoshInstruction.version)
    #expect(throws: ProtoReader.Malformed.self) { try MoshInstruction(Data([0x32, 0x05, 0x00])) }
}

@Test func userAndHostMessagesRoundTrip() throws {
    let user: [MoshUserEvent] = [.resize(columns: 80, rows: 24), .keystroke(Data("ls\r".utf8))]
    let encoded = MoshUserEvent.encode(user)
    // UserMessage{instruction{resize{width 80, height 24}}}, byte for byte.
    #expect(encoded.prefix(8) == hex("0A06 1A04 2850 3018"))
    #expect(try MoshUserEvent.decode(encoded) == user)

    let host: [MoshHostEvent] = [.resize(columns: 132, rows: 50),
                                 .hostBytes(Data("\u{1b}[Hhi".utf8)), .echoAck(17)]
    #expect(try MoshHostEvent.decode(MoshHostEvent.encode(host)) == host)
}

@Test func aWholeDatagramGoesOutAndComesBack() throws {
    let cipher = try MoshCipher(key: rfcKey)
    let diff = MoshUserEvent.encode([.keystroke(Data("echo hi\r".utf8))])
    let instruction = MoshInstruction(oldNum: 0, newNum: 1, ackNum: 0, diff: diff)
    let fragments = MoshFragment.split(try Zlib.compress(instruction.encoded), id: 0,
                                       maxContents: 500)
    let grams = try fragments.enumerated().map { n, f in
        try cipher.seal(MoshPacket(sequence: UInt64(n), direction: .toServer, timestamp: 5,
                                   timestampReply: MoshPacket.noTimestamp, payload: f.encoded))
    }

    var assembly = MoshFragmentAssembly()
    var joined: Data?
    for g in grams { joined = assembly.add(MoshFragment(try cipher.open(g).payload)!) }
    let back = try MoshInstruction(try Zlib.decompress(try #require(joined)))
    #expect(back == instruction)
    #expect(try MoshUserEvent.decode(back.diff) == [.keystroke(Data("echo hi\r".utf8))])
}
