import Testing
@testable import pockterm

@Test func toolSpecsCoverTheAgentSurface() {
    let names = AgentTools.specs.map(\.name).sorted()
    #expect(names == ["list_files", "open_session", "read_file",
                      "run_command", "save_snippet", "write_file"])
    for spec in AgentTools.specs {
        #expect(spec.parameters["type"] as? String == "object")
        #expect(!spec.description.isEmpty)
    }
}

@Test func mutationRoutingMatchesToolAndCommand() {
    func call(_ name: String, _ json: String) -> ToolCall {
        ToolCall(id: "t", name: name, argumentsJSON: json)
    }
    #expect(AgentTools.isMutating(call("read_file", #"{"path":"/a"}"#)) == false)
    #expect(AgentTools.isMutating(call("list_files", #"{"path":"/a"}"#)) == false)
    #expect(AgentTools.isMutating(call("write_file", #"{"path":"/a","content":"x"}"#)) == true)
    #expect(AgentTools.isMutating(call("open_session", #"{"host":"web"}"#)) == true)
    #expect(AgentTools.isMutating(call("save_snippet", #"{"label":"l","command":"c"}"#)) == true)
    #expect(AgentTools.isMutating(call("run_command", #"{"command":"ls"}"#)) == false)
    #expect(AgentTools.isMutating(call("run_command", #"{"command":"rm -rf /tmp/x"}"#)) == true)
    #expect(AgentTools.isMutating(call("unknown_tool", "{}")) == true)
}
