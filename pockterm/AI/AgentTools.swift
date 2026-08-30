import Foundation

/// Executes one approved tool call and returns the text result handed back to
/// the model. Protocol-backed so AgentLoop tests run without SSH.
protocol AgentToolExecuting {
    func execute(_ call: ToolCall) async -> String
}

/// The agent's tool surface: what each tool is called, what the model is told
/// about it, and its JSON-schema arguments.
enum AgentTools {
    static let specs: [ToolSpec] = [
        ToolSpec(name: "run_command",
                 description: "Run a shell command on the connected host and return its combined stdout and stderr. A non-zero exit is reported as a trailing [exit status N] line, not an error. Long output is truncated. Runs on a separate channel; the user's interactive terminal is not affected.",
                 parameters: schema(["command": ["type": "string", "description": "The shell command to run"]], required: ["command"])),
        ToolSpec(name: "read_file",
                 description: "Read a text file from the connected host over SFTP.",
                 parameters: schema(["path": ["type": "string", "description": "Absolute or home-relative file path"]], required: ["path"])),
        ToolSpec(name: "write_file",
                 description: "Create or overwrite a text file on the connected host over SFTP.",
                 parameters: schema(["path": ["type": "string"],
                                     "content": ["type": "string"]], required: ["path", "content"])),
        ToolSpec(name: "list_files",
                 description: "List a directory on the connected host over SFTP.",
                 parameters: schema(["path": ["type": "string", "description": "Directory path; defaults to home"]], required: [])),
        ToolSpec(name: "open_session",
                 description: "Open a new terminal session to one of the user's saved hosts, by its label.",
                 parameters: schema(["host": ["type": "string", "description": "The saved host's label"]], required: ["host"])),
        ToolSpec(name: "save_snippet",
                 description: "Save a reusable command snippet in the app.",
                 parameters: schema(["label": ["type": "string"],
                                     "command": ["type": "string"]], required: ["label", "command"])),
    ]

    /// Risk routing for "confirm risky only": run_command defers to the
    /// command classifier; everything else is static per tool. Unknown tools
    /// are mutating.
    static func isMutating(_ call: ToolCall) -> Bool {
        switch call.name {
        case "read_file", "list_files":
            return false
        case "run_command":
            let command = call.arguments()["command"] as? String ?? ""
            return RiskClassifier.classify(command) == .mutating
        default:
            return true
        }
    }

    private static func schema(_ properties: [String: Any], required: [String]) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required]
    }
}
