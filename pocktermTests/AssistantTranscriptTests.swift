import Foundation
import Testing
@testable import pockterm

// Pure transcript rules only. The SwiftData side is deliberately not exercised
// here: this project's unit tests stall for minutes the moment a @Model graph
// is walked, which is why the store is keyed by a plain UUID and why all the
// logic worth testing lives in values.

private func user(_ text: String) -> AssistantMessage {
    AssistantMessage(role: .user, text: text)
}

private func assistant(_ text: String) -> AssistantMessage {
    AssistantMessage(role: .assistant, text: text)
}

private func tool(name: String, result: String? = nil, denied: Bool = false) -> AssistantMessage {
    var message = AssistantMessage(role: .tool, text: "", toolName: name, toolDetail: "ls")
    message.toolResult = result
    message.denied = denied
    return message
}

@Test func roleRoundTripsThroughItsRawValue() {
    for role in [AssistantMessage.Role.user, .assistant, .tool] {
        #expect(AssistantMessage.Role(rawValue: role.rawValue) == role)
    }
}

@Test func shortTranscriptsAreKeptWhole() {
    let messages = [user("one"), assistant("two")]
    #expect(AssistantTranscript.pruned(messages).count == 2)
}

/// A transcript carries terminal output, so it grows faster than a chat log and
/// has to be capped rather than left to fill the device.
@Test func longTranscriptsKeepTheMostRecentTurns() {
    let messages = (1...250).map { user("turn \($0)") }
    let kept = AssistantTranscript.pruned(messages)

    #expect(kept.count == AssistantTranscript.maxTurns)
    #expect(kept.first?.text == "turn 51")
    #expect(kept.last?.text == "turn 250")
}

@Test func pruningToZeroKeepsNothing() {
    #expect(AssistantTranscript.pruned([user("one")], limit: 0).isEmpty)
}

/// `send` appends an empty assistant turn as a placeholder before the first
/// token arrives. Storing it would reload as a blank bubble.
@Test func emptyPlaceholderTurnsAreNotStored() {
    let kept = AssistantTranscript.persistable([user("hello"), assistant("")])

    #expect(kept.count == 1)
    #expect(kept.first?.role == .user)
}

/// A tool turn with no result never finished — usually the app went away
/// mid-call. Reloading it would strand a spinner that can never resolve.
@Test func unfinishedToolCallsAreNotStored() {
    let kept = AssistantTranscript.persistable([
        user("what is running?"),
        tool(name: "run_command", result: "root 1 systemd"),
        tool(name: "run_command"),
    ])

    #expect(kept.count == 2)
    #expect(kept.last?.toolResult == "root 1 systemd")
}

/// A denied call is a real outcome and worth keeping: it records that the
/// assistant asked and the user said no.
@Test func deniedToolCallsAreStored() {
    let kept = AssistantTranscript.persistable([tool(name: "write_file", denied: true)])
    #expect(kept.count == 1)
    #expect(kept.first?.denied == true)
}

@Test func emptyUserTurnsAreNotStored() {
    #expect(AssistantTranscript.persistable([user("")]).isEmpty)
}

/// Order has to survive the round trip: a transcript read back out of order
/// would attribute answers to the wrong questions.
@Test func persistableKeepsOriginalOrder() {
    let kept = AssistantTranscript.persistable([
        user("first"), assistant("second"),
        tool(name: "run_command", result: "third"), user("fourth"),
    ])
    #expect(kept.map(\.text) == ["first", "second", "", "fourth"])
    #expect(kept.map(\.role) == [.user, .assistant, .tool, .user])
}
