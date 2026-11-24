import Testing
@testable import pockterm

@Test func backoffStartsFastAndIsCapped() {
    #expect(Reconnect.delay(beforeAttempt: 1) == .seconds(1))
    #expect(Reconnect.delay(beforeAttempt: 2) == .seconds(2))
    let all = (1...Reconnect.delays.count).compactMap { Reconnect.delay(beforeAttempt: $0) }
    #expect(all.count == Reconnect.delays.count)
    #expect(all.allSatisfy { $0 <= .seconds(30) })
    #expect(all == all.sorted())
}

@Test func backoffGivesUpAfterTheLastAttempt() {
    #expect(Reconnect.delay(beforeAttempt: Reconnect.delays.count + 1) == nil)
    #expect(Reconnect.delay(beforeAttempt: 0) == nil)
    // Never a tight loop against a dead server: a few minutes in all.
    let total = Reconnect.delays.reduce(0, +)
    #expect(total >= 120 && total <= 300)
}

@Test func aDroppedConnectionReconnectsWhenItIsOn() {
    #expect(Reconnect.response(to: .connectionLost, wasConnected: true,
                               userDisconnected: false, autoReconnect: true) == .reconnect)
    #expect(Reconnect.response(to: .connectionLost, wasConnected: true,
                               userDisconnected: false, autoReconnect: false) == .showConnectionLost)
}

@Test func typingExitClosesTheSessionInsteadOfReconnecting() {
    #expect(Reconnect.response(to: .exited, wasConnected: true,
                               userDisconnected: false, autoReconnect: true) == .showClosed)
}

@Test(arguments: [ShellEnd.exited, .connectionLost])
func aSessionTheUserClosedNeverReconnects(end: ShellEnd) {
    #expect(Reconnect.response(to: end, wasConnected: true,
                               userDisconnected: true, autoReconnect: true) == .ignore)
}

@Test(arguments: [ShellEnd.exited, .connectionLost])
func aSessionAlreadyGoingDownIsLeftAlone(end: ShellEnd) {
    // Idle disconnect, or a reconnect already under way.
    #expect(Reconnect.response(to: end, wasConnected: false,
                               userDisconnected: false, autoReconnect: true) == .ignore)
}

@Test func tmuxIsFoundFromItsPath() {
    #expect(Reconnect.tmuxAvailable(probeOutput: "/usr/bin/tmux\n"))
    #expect(Reconnect.tmuxAvailable(probeOutput: "/opt/homebrew/bin/tmux\n"))
}

@Test func tmuxIsMissingWhenTheProbeFails() {
    #expect(!Reconnect.tmuxAvailable(probeOutput: "\n[exit status 1]"))
    #expect(!Reconnect.tmuxAvailable(probeOutput: ""))
}

@Test func tmuxCommandAttachesOrCreatesTheSameSession() {
    #expect(Reconnect.tmuxCommand == "tmux new -A -s pockterm")
}

@Test func reconnectSettingsInheritHostThenGroupThenGlobal() {
    typealias E = EffectiveHostSettings
    #expect(E.resolveFlag(hostValue: false, chain: [true], globalDefault: true) == false)
    #expect(E.resolveFlag(hostValue: nil, chain: [nil, false], globalDefault: true) == false)
    #expect(E.resolveFlag(hostValue: nil, chain: [true, false], globalDefault: false) == true)
    #expect(E.resolveFlag(hostValue: nil, chain: [], globalDefault: true) == true)
    #expect(E.resolveFlag(hostValue: nil, chain: [nil], globalDefault: false) == false)
}

@Test @MainActor func reconnectIsOnAndTmuxOffOutOfTheBox() {
    let settings = ConnectionSettings()
    #expect(settings.autoReconnect)
    #expect(!settings.tmuxAttach)
}
