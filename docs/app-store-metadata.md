# Pockterm — App Store Connect metadata (draft)

Paste these into App Store Connect. Character limits noted; tighten to taste.

## Name (max 30)
Pockterm — SSH & SFTP Client

## Subtitle (max 30)
Terminal, keys & AI assistant

## Promotional text (max 170, editable anytime without review)
A fast, native SSH and SFTP client for iPhone and iPad. Manage hosts and keys, forward ports,
transfer files, and get help from an optional AI assistant using your own API key.

## Description (max 4000)
Pockterm is a native SSH and SFTP client built for iPhone and iPad.

CONNECT
- SSH into your servers with passwords or Ed25519/RSA keys
- Trusted host-key verification warns you if a server's key ever changes
- Multiple live sessions; minimize one and pick it back up from the tab bar

MANAGE
- Organize hosts into groups
- Save reusable command snippets
- Generate and store SSH keys in the iOS Keychain
- Set up local and remote port forwards

TRANSFER
- Browse, upload, and download files over SFTP

AI ASSISTANT (optional)
- Ask an AI assistant about terminal output and get suggested commands
- Bring your own API key — Anthropic, OpenAI, OpenRouter, or Hugging Face
- Off by default; you're told which provider receives data before anything is sent

PRIVACY
- No account, no Pockterm servers, no tracking or analytics
- Credentials and keys live in the iOS Keychain
- Your connection data stays on your device

## Keywords (max 100, comma-separated, no spaces)
ssh,sftp,terminal,shell,console,server,port forward,tunnel,ssh client,devops,sysadmin,ai

## Support URL
https://github.com/jhancock1975/pockterm   (or a dedicated support page)

## Marketing URL (optional)
https://github.com/jhancock1975/pockterm

## Privacy Policy URL (required)
<public URL where you host docs/privacy-policy.md>

## Category
Primary: Developer Tools    Secondary: Utilities

## Age Rating
4+ (no objectionable content). Note: the app connects to arbitrary user servers, but that
is user-supplied content, not app content.

---

## App Review Notes (CRITICAL — put in the "Notes" field)
Pockterm is an SSH/SFTP client. To review the core functionality you need a server to
connect to. Please use the following demo host:

    Host: <demo-host-or-ip>
    Port: 22
    Username: <demo-user>
    Password: <demo-password>       (or attach a demo private key)

Steps: open the Hosts tab → tap + → enter the above → Connect. You'll get a live shell.
For SFTP, open the connected session's file browser. The AI Assistant (Settings → AI
Assistant) is optional and requires the reviewer's own provider API key; it can be skipped
for review.

Notes on guidelines:
- The app executes commands only on the user's own remote servers over SSH. It does not
  download or execute code that changes the app itself (2.5.2).
- No account system, so no in-app account deletion is required (5.1.1(v)); users can delete
  all stored hosts/keys/credentials in-app and by removing the app.
- The AI Assistant transmits terminal output to a user-configured, user-authenticated
  third-party provider; this is disclosed in-app before sending and in the privacy policy
  (5.1.2).

## ACTION ITEMS you must complete before submitting
1. Stand up a throwaway demo SSH host and fill in the credentials above (biggest rejection risk).
2. Host the privacy policy and paste its URL.
3. Answer export compliance (see docs/app-store-submission.md §0b).
4. Capture screenshots: 6.9" iPhone and 13" iPad (device family is 1,2).
