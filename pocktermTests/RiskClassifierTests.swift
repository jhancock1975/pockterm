import Testing
@testable import pockterm

@Test(arguments: [
    ("ls -la /var/log", CommandRisk.readOnly),
    ("cat /etc/nginx/nginx.conf", .readOnly),
    ("grep -r error /var/log | head -20", .readOnly),
    ("git status && git log --oneline -5", .readOnly),
    ("df -h; uptime", .readOnly),
    ("rm -rf build", CommandRisk.mutating),
    ("sudo systemctl restart nginx", .mutating),
    ("echo hi > /tmp/x", .mutating),          // redirection writes
    ("cat a.txt >> b.txt", .mutating),
    ("ls && rm x", .mutating),                 // any risky segment taints all
    ("frobnicate --all", .mutating),           // unknown ⇒ risky
    ("find . -name '*.log' -delete", .mutating),
])
func classifiesCommands(_ command: String, _ expected: CommandRisk) {
    #expect(RiskClassifier.classify(command) == expected)
}

/// Commands that read as harmless from their first word but execute something
/// else entirely. Each one was classified `.readOnly` before hardening, so in
/// "confirm risky only" mode the agent ran them with no user confirmation.
@Test(arguments: [
    "echo $(rm -rf ~)",                        // command substitution
    "echo `rm -rf ~`",                         // backtick substitution
    "cat <(rm -rf ~)",                         // process substitution
    "env rm -rf ~",                            // env execs its argv
    "awk 'BEGIN{system(\"rm -rf ~\")}'",       // awk embeds a language
    "sed 's/a/b/e' file",                      // GNU sed `e` executes
    "find . -execdir rm {} +",                 // -execdir slipped past -exec
    "find . -fprintf /etc/passwd x",           // -fprintf writes a file
    "git -c core.pager=rm\\ -rf\\ ~ log",      // config injection runs the pager
    "git push origin main",                    // not on the read-only allowlist
    "man ls",                                  // pager executes
    "less /etc/passwd",                        // less can shell out
])
func treatsDisguisedExecutionAsMutating(_ command: String) {
    #expect(RiskClassifier.classify(command) == .mutating)
}
