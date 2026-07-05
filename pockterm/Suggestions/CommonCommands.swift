import Foundation

/// A small curated list of frequently used shell commands, offered as fallback
/// suggestions when history and snippets don't cover what the user is typing.
enum CommonCommands {
    static let all: [String] = [
        "ls", "ls -la", "cd", "cd ..", "pwd", "cat", "less", "tail -f", "head",
        "grep", "grep -r", "find", "df -h", "du -sh", "free -h", "top", "htop",
        "ps aux", "kill", "chmod", "chown", "mkdir", "rm -rf", "cp", "mv", "ln -s",
        "tar -xzf", "tar -czf", "curl", "wget", "ssh", "scp", "rsync -av",
        "systemctl status", "systemctl restart", "journalctl -f", "service",
        "docker ps", "docker logs", "docker compose up -d", "docker compose down",
        "git status", "git pull", "git push", "git log --oneline", "git diff",
        "git add .", "git commit -m", "git checkout", "git branch",
        "sudo", "sudo su", "apt update", "apt install", "yum install", "brew install",
        "vim", "nano", "export", "env", "history", "clear", "exit", "whoami", "uname -a",
    ]
}
