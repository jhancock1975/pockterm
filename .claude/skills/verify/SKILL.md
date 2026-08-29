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
