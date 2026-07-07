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
