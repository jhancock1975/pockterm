# Pockterm Privacy Policy

_Last updated: 2026-07-11_

Pockterm is an SSH/SFTP terminal client for iPhone and iPad. This policy explains what
data the app handles. **Host it at a public URL** (a website, GitHub Pages, a Notion or
Google Doc set to public) and paste that URL into App Store Connect → App Privacy →
Privacy Policy URL.

## Summary

Pockterm has no user accounts and runs no servers of its own. Your connection data stays
on your device. The one time data leaves your device is when **you** use the AI Assistant,
which sends data to a model provider **you** choose, using **your own** API key.

## Data stored on your device

The following are stored locally and never uploaded by Pockterm:

- **Connection profiles** — host names, ports, usernames, groups, snippets, and port-forward
  definitions. Stored in the app's on-device database.
- **Passwords and SSH private keys** — stored in the **iOS Keychain**.
- **Trusted host keys** — remembered on-device so the app can warn you if a server's key
  later changes.
- **AI provider API keys** — stored in the **iOS Keychain**.

Deleting the app removes this data. You can also delete individual hosts, keys, and
credentials from within the app at any time.

## Data you send to remote servers

Pockterm connects to the SSH/SFTP servers **you** specify and transmits the commands, input,
and file transfers **you** initiate, over an encrypted SSH connection. Pockterm does not
route this traffic through any Pockterm-operated server; it goes directly from your device
to your server.

## Data sent to AI providers (only when you use the AI Assistant)

The AI Assistant is optional and off until you configure it. When you use it, Pockterm sends
the relevant terminal output and any files you attach to the model provider you have selected —
**Anthropic, OpenAI, OpenRouter, or Hugging Face** — authenticated with the API key you
provide. The app tells you which provider will receive the data before it is sent.

Pockterm does not receive or store a copy of this data on any Pockterm server. How the
provider handles it is governed by that provider's own privacy policy:

- Anthropic: https://www.anthropic.com/legal/privacy
- OpenAI: https://openai.com/policies/privacy-policy
- OpenRouter: https://openrouter.ai/privacy
- Hugging Face: https://huggingface.co/privacy

## Analytics and tracking

Pockterm contains **no** analytics, advertising, or third-party tracking SDKs. It does not
collect usage data and does not track you across other apps or websites.

## Children

Pockterm is a developer/IT tool and is not directed at children.

## Contact

Questions about this policy: jhancock1975@gmail.com
