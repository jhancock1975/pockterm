import Compression
import Foundation

// The mosh wire format, from the outside in:
//
//   UDP datagram = 8-byte nonce tail ‖ AES-128-OCB(plaintext) ‖ 16-byte tag
//   plaintext    = timestamp (u16) ‖ timestamp reply (u16) ‖ fragment
//   fragment     = instruction id (u64) ‖ final bit + fragment number (u16) ‖ bytes
//   fragments of one id, joined, = zlib(Instruction protobuf)
//   Instruction.diff = UserMessage (client → server) or HostMessage (back)
//
// All integers are big-endian. Written from the protocol, not from mosh's
// source, which is GPLv3.

// MARK: - Session key

nonisolated enum MoshKey {
    /// `mosh-server` prints the key as 22 characters of unpadded base64.
    static func decode(_ printed: String) -> Data? {
        let text = printed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count == 22, let key = Data(base64Encoded: text + "==") else { return nil }
        return key.count == 16 ? key : nil
    }
}

// MARK: - Packets

nonisolated enum MoshDirection: Equatable, Sendable {
    case toServer, toClient
}

nonisolated struct MoshPacket: Equatable, Sendable {
    /// Per-direction counter; never repeats under one key.
    var sequence: UInt64
    var direction: MoshDirection
    /// Milliseconds, mod 2^16.
    var timestamp: UInt16
    /// The peer's last timestamp, aged by how long we held it, or
    /// `noTimestamp`.
    var timestampReply: UInt16
    var payload: Data

    static let noTimestamp: UInt16 = 0xFFFF
    static let directionBit: UInt64 = 1 << 63
}

/// Seals and opens datagrams under one session key.
nonisolated final class MoshCipher {
    private let ocb: AESOCB

    init(key: Data) throws { ocb = try AESOCB(key: key) }

    func seal(_ p: MoshPacket) throws -> Data {
        let tail = (p.sequence & ~MoshPacket.directionBit)
            | (p.direction == .toClient ? MoshPacket.directionBit : 0)
        var nonceTail = Data()
        nonceTail.appendBE(tail)
        var plain = Data()
        plain.appendBE(p.timestamp)
        plain.appendBE(p.timestampReply)
        plain.append(p.payload)
        return nonceTail + (try ocb.seal(plain, nonce: Data(count: 4) + nonceTail))
    }

    func open(_ datagram: Data) throws -> MoshPacket {
        guard datagram.count >= 8 + AESOCB.tagLength + 4 else { throw AESOCB.Failure.tooShort }
        let nonceTail = datagram.prefix(8)
        let plain = try ocb.open(datagram.dropFirst(8), nonce: Data(count: 4) + nonceTail)
        let tail = nonceTail.readBE(UInt64.self, at: 0)
        return MoshPacket(sequence: tail & ~MoshPacket.directionBit,
                          direction: tail & MoshPacket.directionBit != 0 ? .toClient : .toServer,
                          timestamp: plain.readBE(UInt16.self, at: 0),
                          timestampReply: plain.readBE(UInt16.self, at: 2),
                          payload: Data(plain.dropFirst(4)))
    }
}

// MARK: - Fragments

nonisolated struct MoshFragment: Equatable, Sendable {
    var id: UInt64
    var number: UInt16
    var isFinal: Bool
    var contents: Data

    static let headerLength = 10

    var encoded: Data {
        var d = Data()
        d.appendBE(id)
        d.appendBE(number | (isFinal ? 0x8000 : 0))
        d.append(contents)
        return d
    }

    init(id: UInt64, number: UInt16, isFinal: Bool, contents: Data) {
        self.id = id; self.number = number; self.isFinal = isFinal; self.contents = contents
    }

    init?(_ data: Data) {
        guard data.count >= Self.headerLength else { return nil }
        id = data.readBE(UInt64.self, at: 0)
        let n = data.readBE(UInt16.self, at: 8)
        number = n & 0x7FFF
        isFinal = n & 0x8000 != 0
        contents = Data(data.dropFirst(Self.headerLength))
    }

    /// Splits one instruction's compressed bytes into fragments whose
    /// contents fit `maxContents`.
    static func split(_ data: Data, id: UInt64, maxContents: Int) -> [MoshFragment] {
        precondition(maxContents > 0)
        var out: [MoshFragment] = []
        var start = data.startIndex
        repeat {
            let end = min(start + maxContents, data.endIndex)
            out.append(MoshFragment(id: id, number: UInt16(out.count), isFinal: end == data.endIndex,
                                    contents: Data(data[start..<end])))
            start = end
        } while start < data.endIndex
        return out
    }
}

/// Reassembles fragments, which can arrive out of order. Only the newest
/// instruction is kept: one that started arriving is abandoned as soon as a
/// fragment of a different instruction shows up, since mosh resends whole
/// states rather than repairing old ones.
nonisolated struct MoshFragmentAssembly {
    private var id: UInt64?
    private var parts: [UInt16: Data] = [:]
    private var total: Int?

    /// The joined bytes once every fragment of an instruction is in.
    mutating func add(_ f: MoshFragment) -> Data? {
        if id != f.id {
            id = f.id; parts = [:]; total = nil
        }
        parts[f.number] = f.contents
        if f.isFinal { total = Int(f.number) + 1 }
        guard let total, parts.count == total else { return nil }
        var joined = Data()
        for n in 0..<total {
            guard let p = parts[UInt16(n)] else { return nil }
            joined.append(p)
        }
        id = nil; parts = [:]; self.total = nil
        return joined
    }
}

// MARK: - zlib

/// zlib streams (RFC 1950): a 2-byte header, raw deflate, and an Adler-32.
/// The Compression framework speaks only the raw deflate in the middle.
nonisolated enum Zlib {
    enum Failure: Error { case badHeader, badChecksum, codec }

    static func compress(_ data: Data) throws -> Data {
        var out = Data([0x78, 0x9C])
        out.append(try run(COMPRESSION_STREAM_ENCODE, data))
        out.appendBE(adler32(data))
        return out
    }

    static func decompress(_ data: Data) throws -> Data {
        guard data.count >= 6 else { throw Failure.badHeader }
        let cmf = data[data.startIndex], flg = data[data.startIndex + 1]
        guard cmf & 0x0F == 8, (UInt16(cmf) << 8 | UInt16(flg)) % 31 == 0, flg & 0x20 == 0
        else { throw Failure.badHeader }
        let body = data.dropFirst(2).dropLast(4)
        let out = try run(COMPRESSION_STREAM_DECODE, Data(body))
        guard adler32(out) == data.readBE(UInt32.self, at: data.count - 4) else {
            throw Failure.badChecksum
        }
        return out
    }

    static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return b << 16 | a
    }

    private static func run(_ op: compression_stream_operation, _ input: Data) throws -> Data {
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, op, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw Failure.codec
        }
        defer { compression_stream_destroy(stream) }

        let chunk = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { buffer.deallocate() }
        var out = Data()
        return try input.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Data in
            stream.pointee.src_ptr = src.bindMemory(to: UInt8.self).baseAddress
                ?? UnsafePointer(buffer)
            stream.pointee.src_size = input.count
            while true {
                stream.pointee.dst_ptr = buffer
                stream.pointee.dst_size = chunk
                let status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                out.append(buffer, count: chunk - stream.pointee.dst_size)
                switch status {
                case COMPRESSION_STATUS_OK: continue
                case COMPRESSION_STATUS_END: return out
                default: throw Failure.codec
                }
            }
        }
    }
}

// MARK: - Protobuf (the handful of messages mosh uses, proto2)

nonisolated struct ProtoWriter {
    private(set) var data = Data()

    mutating func varint(_ field: Int, _ value: UInt64) {
        raw(UInt64(field << 3))
        raw(value)
    }

    mutating func bytes(_ field: Int, _ value: Data) {
        raw(UInt64(field << 3 | 2))
        raw(UInt64(value.count))
        data.append(value)
    }

    private mutating func raw(_ v: UInt64) {
        var v = v
        while v >= 0x80 {
            data.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        data.append(UInt8(v))
    }
}

nonisolated enum ProtoValue: Equatable {
    case varint(UInt64)
    case bytes(Data)
}

nonisolated enum ProtoReader {
    struct Malformed: Error {}

    /// Every field in order. Fixed-width fields, which mosh never sends, are
    /// skipped.
    static func fields(_ data: Data) throws -> [(Int, ProtoValue)] {
        var out: [(Int, ProtoValue)] = []
        var i = data.startIndex
        func varint() throws -> UInt64 {
            var v: UInt64 = 0, shift: UInt64 = 0
            while true {
                guard i < data.endIndex, shift < 64 else { throw Malformed() }
                let b = data[i]; i += 1
                v |= UInt64(b & 0x7F) << shift
                if b & 0x80 == 0 { return v }
                shift += 7
            }
        }
        while i < data.endIndex {
            let key = try varint()
            let field = Int(key >> 3)
            switch key & 7 {
            case 0: out.append((field, .varint(try varint())))
            case 2:
                let n = try varint()
                guard n <= UInt64(data.endIndex - i) else { throw Malformed() }
                let end = i + Int(n)
                out.append((field, .bytes(Data(data[i..<end]))))
                i = end
            case 1: guard data.endIndex - i >= 8 else { throw Malformed() }; i += 8
            case 5: guard data.endIndex - i >= 4 else { throw Malformed() }; i += 4
            default: throw Malformed()
            }
        }
        return out
    }
}

/// TransportBuffers.Instruction: one step of the state sync, in either
/// direction. `diff` turns state `oldNum` into state `newNum`.
nonisolated struct MoshInstruction: Equatable, Sendable {
    var protocolVersion: UInt32 = MoshInstruction.version
    var oldNum: UInt64 = 0
    var newNum: UInt64 = 0
    var ackNum: UInt64 = 0
    var throwawayNum: UInt64 = 0
    var diff = Data()
    var chaff = Data()

    static let version: UInt32 = 2

    var encoded: Data {
        var w = ProtoWriter()
        w.varint(1, UInt64(protocolVersion))
        w.varint(2, oldNum)
        w.varint(3, newNum)
        w.varint(4, ackNum)
        w.varint(5, throwawayNum)
        if !diff.isEmpty { w.bytes(6, diff) }
        if !chaff.isEmpty { w.bytes(7, chaff) }
        return w.data
    }

    init(oldNum: UInt64 = 0, newNum: UInt64 = 0, ackNum: UInt64 = 0, throwawayNum: UInt64 = 0,
         diff: Data = Data(), chaff: Data = Data()) {
        self.oldNum = oldNum; self.newNum = newNum; self.ackNum = ackNum
        self.throwawayNum = throwawayNum; self.diff = diff; self.chaff = chaff
    }

    init(_ data: Data) throws {
        for (field, value) in try ProtoReader.fields(data) {
            switch (field, value) {
            case (1, .varint(let v)): protocolVersion = UInt32(truncatingIfNeeded: v)
            case (2, .varint(let v)): oldNum = v
            case (3, .varint(let v)): newNum = v
            case (4, .varint(let v)): ackNum = v
            case (5, .varint(let v)): throwawayNum = v
            case (6, .bytes(let v)): diff = v
            case (7, .bytes(let v)): chaff = v
            default: break
            }
        }
    }
}

/// What the client sends: keystrokes and window sizes (ClientBuffers).
nonisolated enum MoshUserEvent: Equatable, Sendable {
    case keystroke(Data)
    case resize(columns: Int, rows: Int)

    /// A UserMessage carrying these events, one instruction each.
    static func encode(_ events: [MoshUserEvent]) -> Data {
        var message = ProtoWriter()
        for event in events {
            var inner = ProtoWriter()
            switch event {
            case .keystroke(let keys):
                var k = ProtoWriter(); k.bytes(4, keys)
                inner.bytes(2, k.data)
            case .resize(let columns, let rows):
                var r = ProtoWriter()
                r.varint(5, UInt64(bitPattern: Int64(columns)))
                r.varint(6, UInt64(bitPattern: Int64(rows)))
                inner.bytes(3, r.data)
            }
            message.bytes(1, inner.data)
        }
        return message.data
    }

    static func decode(_ data: Data) throws -> [MoshUserEvent] {
        var out: [MoshUserEvent] = []
        for case (1, .bytes(let inner)) in try ProtoReader.fields(data) {
            for (field, value) in try ProtoReader.fields(inner) {
                guard case .bytes(let body) = value else { continue }
                let f = try ProtoReader.fields(body)
                switch field {
                case 2:
                    for case (4, .bytes(let keys)) in f { out.append(.keystroke(keys)) }
                case 3:
                    out.append(.resize(columns: intField(5, f), rows: intField(6, f)))
                default: break
                }
            }
        }
        return out
    }
}

/// What the server sends: terminal output that redraws the screen, the
/// window size it drew for, and which keystrokes it has echoed (HostBuffers).
nonisolated enum MoshHostEvent: Equatable, Sendable {
    case hostBytes(Data)
    case resize(columns: Int, rows: Int)
    case echoAck(UInt64)

    static func decode(_ data: Data) throws -> [MoshHostEvent] {
        var out: [MoshHostEvent] = []
        for case (1, .bytes(let inner)) in try ProtoReader.fields(data) {
            for (field, value) in try ProtoReader.fields(inner) {
                guard case .bytes(let body) = value else { continue }
                let f = try ProtoReader.fields(body)
                switch field {
                case 2:
                    for case (4, .bytes(let s)) in f { out.append(.hostBytes(s)) }
                case 3:
                    out.append(.resize(columns: intField(5, f), rows: intField(6, f)))
                case 7:
                    for case (8, .varint(let n)) in f { out.append(.echoAck(n)) }
                default: break
                }
            }
        }
        return out
    }

    static func encode(_ events: [MoshHostEvent]) -> Data {
        var message = ProtoWriter()
        for event in events {
            var inner = ProtoWriter(), body = ProtoWriter()
            switch event {
            case .hostBytes(let s): body.bytes(4, s); inner.bytes(2, body.data)
            case .resize(let c, let r):
                body.varint(5, UInt64(bitPattern: Int64(c)))
                body.varint(6, UInt64(bitPattern: Int64(r)))
                inner.bytes(3, body.data)
            case .echoAck(let n): body.varint(8, n); inner.bytes(7, body.data)
            }
            message.bytes(1, inner.data)
        }
        return message.data
    }
}

private nonisolated func intField(_ n: Int, _ fields: [(Int, ProtoValue)]) -> Int {
    for case (let f, .varint(let v)) in fields where f == n {
        return Int(Int32(truncatingIfNeeded: v))
    }
    return 0
}

// MARK: - Big-endian helpers

extension Data {
    nonisolated mutating func appendBE<T: FixedWidthInteger>(_ v: T) {
        Swift.withUnsafeBytes(of: v.bigEndian) { append(contentsOf: $0) }
    }

    nonisolated func readBE<T: FixedWidthInteger>(_: T.Type, at offset: Int) -> T {
        var v: T = 0
        for j in 0..<MemoryLayout<T>.size {
            v = v << 8 | T(self[startIndex + offset + j])
        }
        return v
    }
}
