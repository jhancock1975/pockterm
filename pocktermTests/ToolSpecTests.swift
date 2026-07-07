import Testing
@testable import pockterm

@Test func toolCallParsesItsArgumentsJSON() {
    let call = ToolCall(id: "1", name: "run_command",
                        argumentsJSON: #"{"command":"ls -la"}"#)
    #expect(call.arguments()["command"] as? String == "ls -la")
    #expect(ToolCall(id: "2", name: "x", argumentsJSON: "not json").arguments().isEmpty)
}
