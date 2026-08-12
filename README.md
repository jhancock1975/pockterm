<div align="center">

<img src="pockterm/Assets.xcassets/AppIcon.appiconset/icon-1024.png" width="120" alt="Pockterm icon">

# Pockterm

**A native SSH and SFTP client for iPhone. Free, with no account and no tracking.**

[![Download on the App Store](https://img.shields.io/badge/Download-App%20Store-0D96F6?logo=apple&logoColor=white)](https://apps.apple.com/app/id6789968094)

</div>

---

Pockterm exists because none of the free iPhone terminals did what I wanted.
Full-screen console apps — `vim`, `htop`, `tmux`, anything drawing a TUI —
render properly instead of turning into garbled text.

## What it does

**Connect**
- SSH with passwords or Ed25519/RSA keys
- Host-key verification that warns you if a server's key ever changes
- Multiple live sessions; minimise one and pick it back up from the tab bar
- Configurable keep-alive so idle sessions stay open

**Transfer**
- Full SFTP browser over the same connection — no extra setup
- Uploads and downloads stream in chunks, so large files don't exhaust memory
- Upload straight from iCloud Drive; save downloads back to Files

**Manage**
- Organise hosts into nested groups that pass down credentials and settings
- Reusable command snippets
- Generate and store SSH keys in the iOS Keychain
- Local and remote port forwarding

**AI assistant** *(optional, off by default)*
- Ask about terminal output and get suggested commands
- Bring your own API key: Anthropic, OpenAI, OpenRouter, or Hugging Face
- You're told which provider receives data before anything is sent

## Privacy

No account. No Pockterm servers. No analytics, no tracking, no ads.

Credentials and keys live in the iOS Keychain, and your connection data stays on
your device. The only network traffic is to the servers you configure — plus, if
you deliberately enable the AI assistant, the provider whose key you supplied.

Full policy: [docs/privacy-policy.md](docs/privacy-policy.md)

## Requirements

iOS 18.0 or later, on iPhone or iPad.

## Building

```bash
git clone https://github.com/jhancock1975/pockterm.git
cd pockterm
open pockterm.xcodeproj
```

Swift Package Manager resolves the dependencies on first build. Signing uses
automatic provisioning, so set your own team in the target's Signing settings.

To run the unit tests:

```bash
scripts/test.sh --build
```

Built on [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) for terminal
emulation and [Citadel](https://github.com/orlandos-nl/Citadel) for SSH.

## Status

Free, and staying that way. Actively developed — see
[docs/backlog.md](docs/backlog.md) for what's next, and
[Issues](https://github.com/jhancock1975/pockterm/issues) for bugs and requests.

## Licence

Apache License 2.0 — see [LICENSE](LICENSE). Third-party components and their
licences are listed in [NOTICE](NOTICE); all are Apache-2.0 or MIT.
