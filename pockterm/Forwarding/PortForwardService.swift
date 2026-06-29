import Foundation
import Citadel
import Crypto
import NIOCore
import NIOPosix
import NIOSSH

/// Owns an SSH connection and a running tunnel (local, dynamic, or remote).
actor PortForwardService {
    private var client: SSHClient?
    private var serverChannel: Channel?
    private var remoteTask: Task<Void, Error>?
    private let group: EventLoopGroup = MultiThreadedEventLoopGroup.singleton

    func connect(_ creds: SSHCredentials,
                 onHostKey: @escaping @Sendable (PresentedHostKey) async -> Bool) async throws {
        let method: SSHAuthenticationMethod
        switch creds.auth {
        case .password(let password):
            method = .passwordBased(username: creds.username, password: password)
        case .ed25519Seed(let seed):
            guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else {
                throw SSHEngineError.invalidKey
            }
            method = .ed25519(username: creds.username, privateKey: key)
        }
        let validator = CallbackHostKeyValidator(address: creds.host, port: creds.port, decide: onHostKey)
        client = try await SSHClient.connect(
            host: creds.host, port: creds.port,
            authenticationMethod: method,
            hostKeyValidator: .custom(validator),
            reconnect: .never)
    }

    /// Listens on `bindHost:bindPort` and forwards each connection to
    /// `targetHost:targetPort` through the SSH tunnel. Returns the bound port.
    func startLocal(bindHost: String, bindPort: Int,
                    targetHost: String, targetPort: Int) async throws -> Int {
        guard let client else { throw SSHEngineError.notConnected }
        let server = try await ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 16)
            .childChannelOption(ChannelOptions.autoRead, value: false)
            .childChannelInitializer { child in
                let promise = child.eventLoop.makePromise(of: Void.self)
                promise.completeWithTask {
                    try await PortForwardService.glue(child: child, client: client,
                                                      host: targetHost, port: targetPort)
                }
                return promise.futureResult
            }
            .bind(host: bindHost, port: bindPort).get()
        serverChannel = server
        return server.localAddress?.port ?? bindPort
    }

    /// Runs a SOCKS5 proxy on `bindHost:bindPort`; each CONNECT is tunneled.
    func startDynamic(bindHost: String, bindPort: Int) async throws -> Int {
        guard let client else { throw SSHEngineError.notConnected }
        let server = try await ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 16)
            .childChannelInitializer { child in
                child.pipeline.addHandler(SOCKS5Handler(client: client))
            }
            .bind(host: bindHost, port: bindPort).get()
        serverChannel = server
        return server.localAddress?.port ?? bindPort
    }

    /// Asks the server to listen on `bindPort` and forwards inbound connections
    /// to `targetHost:targetPort` on the device side.
    func startRemote(bindPort: Int, targetHost: String, targetPort: Int) async throws {
        guard let client else { throw SSHEngineError.notConnected }
        remoteTask = Task {
            try await client.runRemotePortForward(host: "127.0.0.1", port: bindPort,
                                                  forwardingTo: targetHost, port: targetPort)
        }
    }

    func stop() async {
        remoteTask?.cancel()
        remoteTask = nil
        try? await serverChannel?.close()
        serverChannel = nil
        try? await client?.close()
        client = nil
    }

    /// Opens a direct-TCP/IP channel to the target and splices it to `child`.
    private static func glue(child: Channel, client: SSHClient, host: String, port: Int) async throws {
        let origin = child.remoteAddress ?? (try? SocketAddress(ipAddress: "127.0.0.1", port: 0))
            ?? (try! SocketAddress(unixDomainSocketPath: "/dev/null"))
        let remote = try await client.createDirectTCPIPChannel(
            using: .init(targetHost: host, targetPort: port, originatorAddress: origin)
        ) { remoteChannel in
            remoteChannel.setOption(ChannelOptions.autoRead, value: false)
        }
        let (localGlue, remoteGlue) = GlueHandler.matchedPair()
        try await child.pipeline.addHandler(localGlue)
        try await remote.pipeline.addHandler(remoteGlue)
        child.read()
        remote.read()
    }

    fileprivate static func glueExisting(child: Channel, remote: Channel) async throws {
        let (localGlue, remoteGlue) = GlueHandler.matchedPair()
        try await child.pipeline.addHandler(localGlue)
        try await remote.pipeline.addHandler(remoteGlue)
        child.read()
        remote.read()
    }
}

/// Per-connection SOCKS5 front-end for dynamic forwarding: negotiates no-auth,
/// reads the CONNECT target, then opens the tunnel and splices the channels.
final class SOCKS5Handler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer

    private enum State { case greeting, connect, done }
    private var state: State = .greeting
    private var buffer: [UInt8] = []
    private let client: SSHClient

    init(client: SSHClient) { self.client = client }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var incoming = unwrapInboundIn(data)
        buffer.append(contentsOf: incoming.readableBytesView)
        advance(context: context)
    }

    private func advance(context: ChannelHandlerContext) {
        switch state {
        case .greeting:
            guard let ok = SOCKS5.parseGreeting(buffer) else { return }
            let consumed = 2 + Int(buffer[1])
            buffer.removeFirst(min(consumed, buffer.count))
            guard ok else { context.close(promise: nil); return }
            write(context, SOCKS5.greetingReply)
            state = .connect
            if !buffer.isEmpty { advance(context: context) }
        case .connect:
            guard let target = SOCKS5.parseConnect(buffer) else { return }
            state = .done
            openTunnel(context: context, target: target)
        case .done:
            break
        }
    }

    private func openTunnel(context: ChannelHandlerContext, target: SOCKSTarget) {
        let channel = context.channel
        let client = self.client
        let promise = context.eventLoop.makePromise(of: Void.self)
        promise.completeWithTask {
            do {
                let origin = channel.remoteAddress ?? (try! SocketAddress(ipAddress: "127.0.0.1", port: 0))
                let remote = try await client.createDirectTCPIPChannel(
                    using: .init(targetHost: target.host, targetPort: target.port, originatorAddress: origin)
                ) { remoteChannel in
                    remoteChannel.setOption(ChannelOptions.autoRead, value: false)
                }
                self.write(context, SOCKS5.connectReply(success: true))
                try await channel.pipeline.removeHandler(self)
                try await PortForwardService.glueExisting(child: channel, remote: remote)
            } catch {
                self.write(context, SOCKS5.connectReply(success: false))
                channel.close(promise: nil)
            }
        }
    }

    private func write(_ context: ChannelHandlerContext, _ bytes: [UInt8]) {
        var out = context.channel.allocator.buffer(capacity: bytes.count)
        out.writeBytes(bytes)
        context.writeAndFlush(NIOAny(out), promise: nil)
    }
}
