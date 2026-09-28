# Glasses Display Mode

**Date:** 2026-09-28
**Status:** Approved design, ready for planning

## Summary

When video glasses such as VITURE are plugged in, the glasses become the
terminal's screen and the phone becomes its keyboard and file browser. The
glasses show one large landscape view holding only the active session's
terminal: no tab bar, no buttons. The phone keeps the keyboard and key bar
where they always are, and shows the SFTP browser for the active session's
server in the space the terminal normally fills.

To iOS the glasses are an ordinary external display over USB-C, and iOS
cannot tell glasses from a TV or monitor. So the mode applies to any external
display, and it turns itself on and off as the display connects and
disconnects. Nothing changes when no display is attached.

Out of scope:
- VITURE's 3D side-by-side mode (it reports a double-wide screen, which would
  split the terminal across the eyes). Only the normal 2D mode is designed for.
- Showing the terminal on more than one external display.
- Mirroring the phone's normal UI to the glasses.
- The file browser following the shell's working directory.

## Decisions

| Area | Decision |
|---|---|
| Trigger | Automatic. On when an external display scene connects, off when it disconnects. No setting. |
| What the glasses show | The active session's terminal whenever the terminal would be on screen (`SessionManager.isTerminalPresented`); otherwise an idle screen |
| Idle screen | Black, with the Pockterm mark and "Open a session on your phone". Shown when there are no sessions or they're minimized. |
| Terminal instance | The session's existing `TerminalView` moves between windows. There's one emulator and one buffer, and no second terminal. |
| Keyboard on the phone | An invisible `TerminalKeyboardProxy` on the phone is first responder, carries the key bar, and forwards all input to the active terminal |
| Phone content area | `FilesBrowserView` for the active session's host, embedded (not a sheet), with its Done button hidden |
| Session switch | The browser is recreated for the new session's host, starting at its home folder |
| Glasses text size | One app-wide size in `UserDefaults`, separate from the phone's zoom, default 18pt, clamped to `TerminalZoom.minSize…maxSize` (8–32). Changed with A−/A+ on the phone. |
| Font face and theme | Still from the host's resolved settings (`EffectiveHostSettings`) |
| Pty size | Follows the terminal's size on the glasses through the existing `proxy.onSize` → `engine.resize` path |

## 1. Bringing up the glasses scene

The app uses the SwiftUI lifecycle (`pocktermApp`, one `WindowGroup`, a
generated Info.plist with `UIApplicationSceneManifest_Generation = YES`).

- Add an `AppDelegate` through `@UIApplicationDelegateAdaptor`. Its
  `application(_:configurationForConnecting:options:)` returns, for the role
  `.windowExternalDisplayNonInteractive`, a `UISceneConfiguration` whose
  `delegateClass` is `ExternalDisplaySceneDelegate`. For every other role it
  returns the default configuration, so SwiftUI keeps owning the main window.
- `ExternalDisplaySceneDelegate` (a `UIWindowSceneDelegate`) builds a
  `UIWindow` for the scene with a `UIHostingController` whose root is
  `GlassesRootView`. On connect it registers the scene's screen size with
  `ExternalDisplay`, and on `sceneDidDisconnect` it unregisters.
- The scene delegate needs the app's `SessionManager`. Today `AppContainer`
  is a `@State` inside `pocktermApp`. It becomes a single shared instance
  (`AppContainer.shared`, main-actor) that the App and the scene delegate
  both use. The App's behaviour doesn't change.
- Only the first external scene shows the terminal. Any further one shows
  the idle screen.

## 2. `ExternalDisplay`

A main-actor `@Observable` object owned by `AppContainer`:

- `var isConnected: Bool`
- `var size: CGSize` (the glasses scene's bounds)
- `connect(size:)` and `disconnect()`, called by the scene delegate

The phone UI (`SessionTabsView`) and `TerminalSession` observe it to switch
between normal and glasses mode. Every glasses-mode branch keys off
`isConnected`, so with no display attached the app behaves exactly as today.

## 3. `GlassesRootView`

Full-bleed black, ignoring safe areas. Which screen it shows is decided by one
pure function (unit-tested), roughly:

```swift
enum GlassesContent: Equatable { case idle, terminal(TerminalSession.ID) }
static func content(sessions: [ID], activeID: ID?, isMinimized: Bool) -> GlassesContent
```

It returns `.terminal(activeID)` when a session is active and not minimized,
and `.idle` otherwise.

- **Terminal:** `TerminalHostView(terminalView: session.terminalView)`
  filling the display, with the same status overlays `SessionTabsView` uses
  (connecting, failed, closed, idle-disconnected), sized up for the large
  screen. They're display-only here; their buttons live on the phone
  (section 5).
- **Idle:** the Pockterm mark and "Open a session on your phone", localized
  like the rest of the app.

## 4. Moving the terminal view

A `UIView` can be in only one window. In glasses mode the glasses host the
active session's `TerminalView` and the phone never does, so the two never
compete in steady state.

- `TerminalHostView.updateUIView` makes sure its container holds exactly the
  terminal view it was given. If that view's `superview` isn't this
  container, it removes any other terminal view the container still holds,
  adds this one, and re-pins the constraints. This covers handovers in both
  directions (plug in, unplug, session switch) without either side having to
  know about the other.
- On the glasses, the terminal has no keyboard to avoid. Its bottom anchors
  to the container's bottom rather than to `keyboardLayoutGuide`, via a flag
  on `TerminalHostView`.
- On entering glasses mode, `TerminalSession` applies the glasses font size.
  On leaving, it restores `currentFontSize`, the phone's zoom. Both go through
  `applyAppearance()`. The resulting layout reports the new cols/rows through
  `proxy.onSize`, which already calls `engine.resize`.
- `TerminalView.caretViewTracksFocus` is turned off while the proxy holds the
  keyboard, because the caret otherwise checks the terminal's own
  `isFirstResponder`. `Terminal.setTerminalFocus(_:)` follows the proxy's
  first-responder state, so focus-in/out reporting (mode 1004, used by tmux
  and vim) is correct. Both are public SwiftTerm API.

## 5. The phone in glasses mode

`SessionTabsView` keeps its structure. Only the content area and a few
top-bar items change when `ExternalDisplay.isConnected`:

- **Top bar:** unchanged apart from:
  - The Files button is hidden.
  - A glasses text-size control (A− / A+) takes its place and writes the
    app-wide size.
  - A keyboard button appears while the keyboard is hidden, to bring it back.
    With no terminal on the phone, there's nothing else to tap.
  - `ZoomControlsView` isn't shown.
- **Content:** when the active session is `.connected`, an embedded
  `FilesBrowserView` for `session.host`, keyed by session ID so switching
  sessions recreates it. It gets an `embedded` flag that hides its Done button
  (in this spot Done would dismiss the whole terminal cover). Otherwise it
  keeps all its features and opens its own SFTP connection as it does today.
  When the session isn't connected, the phone shows the same status views
  `sessionContent` shows today, with their buttons live (for example "Change
  how long sessions stay connected").
- **Keyboard:** a `TerminalKeyboardProxy` sits behind the content, zero size
  and invisible. It becomes first responder when glasses mode starts or the
  cover appears, so the keyboard and key bar are up where they usually are.
  The file browser fits above them.
  - The key bar's hide-keyboard key resigns the proxy, not the terminal.
  - After a file-browser alert with a text field (new folder, rename,
    permissions) closes, the proxy takes first responder back.
- **Minimize / restore** work as today. The glasses follow through
  `GlassesContent`.
- **Unplugging mid-session:** the terminal goes back to the phone's
  `TerminalHostView` at phone size. If the proxy held the keyboard, the
  terminal view becomes first responder, so typing continues without a tap.
- **Backgrounding:** iOS shows an app's own external-display content only
  while the app is in front. Sessions keep running exactly as today.

## 6. `TerminalKeyboardProxy`

A `UIView` on the phone that adopts `UITextInput` (and therefore
`UIKeyInput`) by forwarding every call to its target `TerminalView`.
SwiftTerm's input methods (`insertText`, `deleteBackward`, `setMarkedText`,
`unmarkText`, the range and position queries) don't check the view's own
first-responder state, and `KeyBarView` already calls
`terminalView.insertText`/`send` directly, so forwarding is enough.

- `var target: TerminalView?`, set to the active session's terminal and
  updated on session switch.
- `inputAccessoryView` returns the target session's `KeyBarView`, the same
  object the terminal carries today.
- `UITextInputTraits` (keyboard type, autocorrection, smart quotes, return
  key) copy the terminal's, so the keyboard behaves identically.
- `inputDelegate` is passed through, so the system's text-input machinery
  sees the terminal's own change notifications.
- `pressesBegan`/`pressesEnded`/`pressesCancelled` forward to the target, so a
  hardware keyboard works too.
- `becomeFirstResponder` and `resignFirstResponder` switch the target's
  terminal focus and caret tracking (section 4).

`KeyBarView.hideKeyboard` currently resigns the terminal view. It is changed
to resign whichever responder is presenting it, which works in both modes.

### First check: is the proxy needed at all?

Before building the proxy, a throwaway simulator probe checks whether a view
in a `.windowExternalDisplayNonInteractive` scene can become first responder
and bring up the phone's keyboard. The expectation is no, because iPhone
external scenes are display-only. If it does work, section 6 is dropped and
the terminal view keeps the keyboard itself. The probe code is not kept.

## 7. Edge cases

- **Host-key prompts, snippets, the theme picker and the AI assistant** are
  already phone alerts, sheets and menus, so they work unchanged. The
  assistant reads the terminal buffer, which doesn't depend on which window
  shows it.
- **RTL languages:** `TerminalHostView` already pins the terminal
  left-to-right, and the same code runs on the glasses.
- **A second external display** shows the idle screen.
- **The display's size changes while connected** (a different mode): the
  scene updates `ExternalDisplay.size`, the view relays out, and the pty
  follows through `onSize`.

## 8. Testing

Simulator only. Never Hanphone17.

**Unit tests (Swift Testing, pure logic, via `scripts/test.sh`):**
- `GlassesContent.content(...)` for: no sessions; an active session; a
  minimized session; an active ID that no longer exists.
- Glasses font size: default, clamping at 8 and 32, and the UserDefaults
  round-trip.
- `TerminalKeyboardProxy` against a real SwiftTerm `TerminalView` with a
  capturing delegate:
  - typed text reaches `send`
  - Backspace sends DEL
  - a marked-text composition (Japanese) commits to the right UTF-8 bytes
  - a key-bar key fired while the proxy is first responder reaches the
    terminal

**End to end, with the repo's verify skill,** over real SSH to this Mac's
sshd:
1. Attach a virtual external display in Device Hub (the simulator exposes
   external display ports).
2. Open a session and confirm the glasses screenshot
   (`simctl io <sim> screenshot --display=…`) shows only the terminal, and the
   phone shows the file browser above the keyboard.
3. Type `tput cols; tput lines` on the simulator keyboard, and confirm the
   numbers match the glasses view, not the phone.
4. Run tmux on the glasses and compare the screenshot against
   `tmux capture-pane`, as the terminal-emulation debugging notes describe.
5. Minimize, and confirm the glasses show the idle screen. Restore, and
   confirm the terminal returns.
6. Detach the display, and confirm the terminal is back on the phone, at
   phone width, and still takes typing.
