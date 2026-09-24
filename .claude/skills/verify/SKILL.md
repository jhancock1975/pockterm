---
name: verify
description: Drive pockterm end-to-end in the simulator over a real SSH connection to the Mac's own sshd — build/launch recipe, XCUITest driver, and evidence capture for verifying UI changes.
---

# Verifying pockterm in the simulator

Host-side click tools (cliclick) fail without Accessibility permission, so UI
driving is done with a **temporary XCUITest target** running inside the
simulator. Real SSH sessions use the Mac's own sshd (`localhost:22` from the
simulator = the Mac) with an app-generated key added to `~/.ssh/authorized_keys`.

## One-time simulator prep

Software keyboard must be visible for keyboard-layout bugs to reproduce:

```bash
osascript -e 'quit app "Simulator"'
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
open -a Simulator
```

## Set up the driver (temporary — revert when done)

```bash
ruby .claude/skills/verify/add_uitest_target.rb   # adds pocktermUITests target
ruby .claude/skills/verify/add_scheme.rb          # adds shared pocktermUI scheme
xcodebuild build-for-testing -project pockterm.xcodeproj -scheme pocktermUI \
  -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation
```

The driver tests live in `.claude/skills/verify/uitests/VerifyDriverUITests.swift`
(referenced by absolute path — no repo source changes). Phases:

1. **testPhase1GenerateKey** — generates an Ed25519 key ("verify") in the app.
   Read the full public key from the app's SwiftData store, then authorize it:
   ```bash
   CONT=$(xcrun simctl get_app_container booted John-Hancock.pockterm data)
   sqlite3 "$CONT/Library/Application Support/default.store" \
     "SELECT ZPUBLICKEYOPENSSH FROM ZSSHKEYRECORD;" >> ~/.ssh/authorized_keys
   ```
   (An entry commented `verify@pockterm` may already be present from earlier runs.)
2. **testPhase2KeyboardFix** — creates identity+host (`john@localhost:22`),
   connects, accepts the TOFU host-key alert, raises the terminal keyboard,
   opens the assistant sheet, asserts the input bar is above the keyboard,
   focused, and typeable. Idempotent: reuses host/key on reruns.
3. **testPhase3AssistantWithoutTerminalKeyboard** — probes the assistant sheet
   without the terminal keyboard up, and after dismiss/reopen.

Run:

```bash
xcodebuild test-without-building -project pockterm.xcodeproj -scheme pocktermUI \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:pocktermUITests/VerifyDriverUITests/testPhase2KeyboardFix \
  -resultBundlePath /tmp/verify.xcresult

xcrun xcresulttool export attachments --path /tmp/verify.xcresult --output-path /tmp/shots
```

Screenshots come out of the xcresult attachments (named `1-connected`,
`3-assistant-sheet`, …). App-side state can always be read from the SwiftData
sqlite store (path above): `ZHOST`, `ZIDENTITY`, `ZSSHKEYRECORD`,
`ZKNOWNHOSTRECORD`.

## Terminal-emulation checks (tmux, emacs)

`testTmuxEmacsModeLine` runs emacs inside tmux over the real SSH session and
screenshots after each redraw-heavy action. Keystrokes are sent from the **Mac**
with `tmux send-keys` (`tmux-drive.sh` beside the driver), because `C-x C-s`
does not survive XCUITest's `typeText`. Ground truth comes from the tmux server
itself:

```bash
tmux -L v capture-pane -p -t v
```

Any row where the app disagrees with that is an emulation defect. This is how
the DECLRMM/Insert-Line corruption was confirmed and then shown fixed — see the
resolved entry in `docs/backlog.md`.

For emulation bugs, prefer a **headless** harness over the simulator: SwiftTerm's
`HeadlessTerminal` + `LocalProcess` drive a real pty on the Mac, so the same
comparison runs in seconds instead of minutes, and a captured byte stream can be
replayed one byte at a time to find the exact sequence that breaks the screen.
Use the simulator only to prove the wiring in the real app.

## Driving the AI assistant end to end

The agent's `run_command` path (model → tool call → `SessionToolExecutor` →
`SSHEngine.exec` → real sshd) can only be checked with a live provider. It is
worth checking, because a defect there is invisible to unit tests: a non-zero
exit used to surface as an opaque Citadel error with the output discarded
(fixed in #59).

**Pass the API key without putting it in the source or a screenshot.**
`xcodebuild` forwards its own environment variables prefixed `TEST_RUNNER_` to
the test runner with the prefix stripped. It must be **exported into
xcodebuild's environment** — passing it as a build-setting argument on the
command line does not work, and would put the key in the process arguments:

```bash
export TEST_RUNNER_OR_KEY="$(tr -d '\n' < ~/Documents/open-router-key)"
xcodebuild test-without-building ... -only-testing:.../testAgentRunCommandEndToEnd
unset TEST_RUNNER_OR_KEY
```

The test reads `ProcessInfo.processInfo.environment["OR_KEY"]` and types it into
the key field, which is a `SecureField`, so screenshots stay safe.

**Selectors that are not obvious.** SwiftUI `Picker` rows are buttons labelled
`'Provider, Anthropic'` and `'Approval, Confirm everything'`, so match with
`label BEGINSWITH`. The assistant's input is a `TextField` with
placeholder `Ask the assistant…` — `app.textViews.firstMatch` grabs the
*terminal* instead. Set Approval to **Auto-run** so no confirmation tap is
needed. `Test Connection` is disabled until a key is stored, so its enabled
state is the reliable signal that the save landed.

**Afterwards, delete the key**: drive Settings → AI Assistant → **Remove**.
That clears it from the simulator Keychain without erasing the simulator, which
would also destroy the host and SSH key the harness depends on.

## Before submitting: log in to the App Review demo host

`DemoHostUITests.testReviewerLogin` does what a reviewer does after
`scripts/provision-demo-host.sh`: new host, new password credentials, connect,
accept the host key, hold the session. The credentials come from the
environment, never from a file in the repo:

```bash
export TEST_RUNNER_DEMO_HOST=$(grep -m1 'Host:' ~/Documents/Apps/pockterm/demo-host.txt | awk '{print $2}')
export TEST_RUNNER_DEMO_PASSWORD=$(grep -m1 'Password:' ~/Documents/Apps/pockterm/demo-host.txt | awk '{print $2}')
xcodebuild test-without-building -project pockterm.xcodeproj -scheme pocktermUI \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:pocktermUITests/DemoHostUITests/testReviewerLogin
```

It prints `HOLDING>>>` once connected and holds for 25 s. Run `who` on the demo
host in that window: the app's session is the one on a `pts`. A plain
`ssh demo@host cmd` gets no pts, so it can't be mistaken for the app.

**Don't check the host's password login with `expect` on this Mac.** It hangs
after sending the password, right or wrong, and looks exactly like a broken
host. Use `SSH_ASKPASS` with `SSH_ASKPASS_REQUIRE=force` and a script that
prints the password. It answers in about 4 s.

## Gotchas

- **Each UI action can stall ~60s**: XCUITest waits for app quiescence and the
  connecting spinner / terminal caret animate forever. A phase-2 run takes
  ~4-5 min. Budget for it; don't kill the run.
- **First TOFU accept is slow** — slow enough that sshd's LoginGraceTime can
  drop the handshake (`NIOCore.ChannelError error 0`, connection failed). The
  accepted key is still stored; **just rerun** — the second attempt skips the
  alert and connects fast.
- **XCUIElement `app.keyboards` frame lies**: it excludes the predictive bar
  (~45pt). Don't assert "field above keyboard frame" — assert `isHittable`,
  which correctly detects predictive-bar coverage, and eyeball the screenshot.
- SwiftUI's automatic keyboard avoidance has the same defect (frame without
  the predictive bar) — that's why AssistantView and TerminalHostView do
  manual avoidance.
- `defaults read com.apple.iphonesimulator` + accessibility snapshots make
  `log show` noisy; app-side debugging is easiest via `NSLog("POCKVERIFY …")`
  and `xcrun simctl spawn booted log show --last 5m --predicate
  'eventMessage CONTAINS "POCKVERIFY"'`.

## Cleanup

```bash
.claude/skills/verify/cleanup.sh
```

**Do not hand-roll this with git.** `Package.resolved` is tracked *inside* the
bundle, at
`pockterm.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`,
so `git checkout -- pockterm.xcodeproj` silently reverts any dependency re-pin
along with the harness target, leaving no diff to notice afterwards. The script
restores `project.pbxproj` from the snapshot `add_uitest_target.rb` takes,
deletes only the `pocktermUI` scheme, and then fails loudly if `Package.resolved`
moved or the harness target survived.

Clean up **before** running anything against the `pockterm` scheme. That scheme
is autocreated, not shared, and it disappears from `xcodebuild -list` while the
harness target is in the project — `scripts/test.sh` then fails with
`does not contain a scheme named "pockterm"`, which looks like a broken repo
and is only the harness still being installed.

Optionally remove the `verify@pockterm` line from `~/.ssh/authorized_keys` if
the simulator app's key should no longer be able to SSH into the Mac.
