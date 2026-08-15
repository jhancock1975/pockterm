import Foundation

/// A named group of help topics.
struct HelpSection: Identifiable {
    let id = UUID()
    let title: LocalizedStringResource
    let topics: [HelpTopic]
}

/// The user-guide content. Written to be brief, task-focused, and jargon-light.
enum HelpContent {
    static let sections: [HelpSection] = [
        HelpSection(title: "Getting Started", topics: [welcome, addHost, keys]),
        HelpSection(title: "Using Pockterm", topics: [terminal, snippets, organize, importConfig]),
        HelpSection(title: "Files & Networking", topics: [sftp, forwarding]),
        HelpSection(title: "Security & Privacy", topics: [hostKeys, privacy]),
    ]

    static let welcome = HelpTopic(
        title: "Welcome to Pockterm",
        icon: "hand.wave",
        summary: "What Pockterm is and how it's organized",
        blocks: [
            .paragraph("Pockterm is a full-featured SSH client for iPhone. You can connect to servers, run an interactive terminal, transfer files over SFTP, and set up port-forwarding tunnels."),
            .paragraph("Use the tabs along the bottom to move between **Hosts**, **Snippets**, **Keychain**, and **Port Forwarding**."),
            .paragraph("Everything stays on your device — see **Your Data & Privacy** for details."),
        ])

    static let addHost = HelpTopic(
        title: "Adding a Host",
        icon: "server.rack",
        summary: "Create a server you can connect to",
        blocks: [
            .heading("Create a host"),
            .bullets([
                "On the **Hosts** tab, tap **+**, then **New Host**.",
                "Enter a **Label**, the **Address** (hostname or IP), and the **Port** (22 by default).",
                "Choose **Credentials** so Pockterm knows how to sign in. If you don't have any yet, tap **New Credentials**.",
                "Tap **Save**.",
            ]),
            .heading("Host actions"),
            .bullets([
                "**Tap** a host to connect.",
                "**Swipe left** for Edit, Star, or Delete.",
                "**Swipe right** and tap **Files** to browse it over SFTP.",
            ]),
        ])

    static let keys = HelpTopic(
        title: "Credentials & SSH Keys",
        icon: "key.fill",
        summary: "How Pockterm signs you in",
        blocks: [
            .paragraph("**Credentials** are a username plus a way to authenticate — either a password or an SSH key."),
            .heading("Generate a key"),
            .bullets([
                "On the **Keychain** tab, tap **+** and give the key a label.",
                "Pockterm creates an Ed25519 key pair and stores the private key in the iOS Keychain.",
                "Add the shown public-key line to the server's `~/.ssh/authorized_keys` file.",
            ]),
            .heading("Create credentials"),
            .bullets([
                "In a host's editor, choose **New Credentials**.",
                "Enter the username and pick **Password** or **Key**.",
                "For **Key**, select one of the keys you generated.",
            ]),
        ])

    static let terminal = HelpTopic(
        title: "The Terminal",
        icon: "terminal",
        summary: "Connecting and working in a session",
        blocks: [
            .paragraph("Tap a host to open a terminal session."),
            .bullets([
                "The bar above the keyboard has **esc**, **ctrl**, **tab**, arrow keys, and more.",
                "Open several hosts at once — each session is a tab across the top. Tap its name to switch, or the red **✕** to close it.",
                "Tap the **snippet** button to run a saved command in the session.",
            ]),
        ])

    static let snippets = HelpTopic(
        title: "Snippets",
        icon: "text.badge.plus",
        summary: "Save and run reusable commands",
        blocks: [
            .paragraph("Snippets are commands you use often."),
            .bullets([
                "On the **Snippets** tab, tap **+** to save a command with a label.",
                "While connected, tap the snippet button in the terminal to run one.",
                "Give a host a **Startup Snippet** to run it automatically on connect.",
            ]),
        ])

    static let organize = HelpTopic(
        title: "Groups, Favorites & Search",
        icon: "folder",
        summary: "Keep a large host list tidy",
        blocks: [
            .bullets([
                "From the **Hosts** menu, choose **Manage Groups**. Groups can be nested, and a group's default credentials and port are inherited by its hosts.",
                "Assign a host to a group in the host editor.",
                "**Star** a host (swipe left) to pin it to a Favorites section.",
                "Pull down to **search** by label or address. Hosts you've used recently appear under Recents.",
            ]),
        ])

    static let importConfig = HelpTopic(
        title: "Importing from ssh_config",
        icon: "square.and.arrow.down",
        summary: "Bring in existing hosts",
        blocks: [
            .bullets([
                "From the **Hosts** menu, choose **Import from ssh_config**.",
                "Paste your config text, or tap **Choose File**.",
                "Review the detected hosts, turn off any you don't want, then tap **Import**.",
            ]),
            .paragraph("Pockterm reads the `Host`, `HostName`, `User`, and `Port` settings. Password credentials are created for each username so you can fill in the secret afterward."),
        ])

    static let sftp = HelpTopic(
        title: "Transferring Files (SFTP)",
        icon: "folder.badge.gearshape",
        summary: "Browse, download and upload files",
        blocks: [
            .paragraph("Every host has an SFTP file browser. SFTP runs over the same SSH connection, so there is nothing extra to set up."),
            .heading("Open the browser"),
            .bullets([
                "**Long-press a host** and choose **Browse Files**.",
                "Or set the host's **Protocol** to **SFTP (Files)**, and tapping it opens the browser instead of a terminal.",
                "Already in a session? Tap the **folder** button in the terminal's top bar.",
            ]),
            .heading("Download a file"),
            .bullets([
                "**Long-press the file**, then choose **Download**.",
                "It opens in the share sheet, so you can send it anywhere \u{2014} choose **Save to Files** to keep it, including in **iCloud Drive**.",
            ]),
            .heading("Upload a file"),
            .bullets([
                "Tap **+**, then **Upload File**.",
                "That opens the iPhone's own file picker, so you can upload straight from **iCloud Drive**, On My iPhone, or any other Files location.",
                "The file lands in the folder you are currently viewing.",
            ]),
            .heading("Manage files"),
            .bullets([
                "**Long-press** a file to Rename it, change its **Permissions**, or Delete it.",
                "Tap **+** to create a folder. **Pull down** to refresh the listing.",
                "Tap **..** at the top to go up a directory.",
            ]),
            .paragraph("Transfers are streamed in chunks, so even a large file will not exhaust memory. While one runs, the path bar shows how much has transferred and the total size."),
        ])

    static let forwarding = HelpTopic(
        title: "Port Forwarding",
        icon: "arrow.left.arrow.right",
        summary: "Tunnel connections through SSH",
        blocks: [
            .paragraph("Port forwarding routes network connections through an SSH server."),
            .bullets([
                "**Local** — a port on your device forwards to a host the server can reach.",
                "**Remote** — a port on the server forwards back to your device.",
                "**Dynamic** — a SOCKS5 proxy on your device sends each connection through the server.",
            ]),
            .heading("Run a forward"),
            .bullets([
                "On the **Port Forwarding** tab, tap **+** to add one.",
                "**Tap a row** to edit it.",
                "Tap **▶** to start; the status shows when it's active. Tap **⏹** to stop.",
            ]),
        ])

    static let hostKeys = HelpTopic(
        title: "Verifying Host Keys",
        icon: "checkmark.shield",
        summary: "Trusting servers safely",
        blocks: [
            .paragraph("The first time you connect to a server, Pockterm shows its key **fingerprint** and asks you to accept it. This is called trust on first use."),
            .bullets([
                "Accept only if the fingerprint matches what you expect from the server's owner.",
                "Once accepted, the key is remembered and you won't be asked again.",
                "If a server later presents a **different** key, Pockterm warns you before continuing — this can mean the server was rebuilt, or that something is wrong.",
            ]),
        ])

    static let privacy = HelpTopic(
        title: "Your Data & Privacy",
        icon: "lock.shield",
        summary: "Where everything is stored",
        blocks: [
            .paragraph("Pockterm has no account, and your connection data stays on your device."),
            .bullets([
                "Hosts, groups, snippets, and forwards are stored on your device.",
                "Passwords and private keys are kept in the **iOS Keychain**.",
                "Trusted host keys are remembered on your device for the warnings described in **Verifying Host Keys**.",
            ]),
            .paragraph("The **AI Assistant** is the one exception: when you use it, the relevant terminal output (and any files you attach) is sent to the model provider you configure — Anthropic, OpenAI, OpenRouter, or Hugging Face — using **your own API key**. Nothing is sent until you use the assistant, and your key is stored in the iOS Keychain. Review your provider's privacy policy for how they handle that data."),
        ])
}
