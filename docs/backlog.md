# Backlog

Things worth doing, not yet scheduled. Newest first.

---

## Try VoiceStudio for narration the next time the demo videos are rebuilt

**Recorded:** 2026-09-03.

Only the English demo video carries narration. The other fourteen are silent
with burned-in captions, which is what `scripts/build-demo-videos` produces on
purpose — it was the honest option when there was no way to voice fourteen
languages. [VoiceStudio](https://github.com/debpalash/VoiceStudio) is worth a
look next time that script runs.

It is a local, offline TTS and voice-cloning application: 646 languages for
TTS, 16 switchable engines, voice cloning from a 3–15 second reference clip,
and an OpenAI-compatible REST API. Python/FastAPI backend, React front end,
Tauri shell, runs on Apple Silicon. AGPL-3.0, ~16.3k stars, actively
maintained.

### Why it fits here

- **It is a tool, not a dependency.** It would generate audio on this Mac and
  never enter the app's dependency graph, so this does not touch the rules in
  `docs/dependency-policy.md`. AGPL-3.0 covers the application; it does not
  reach the audio it produces.
- **Voice cloning is the interesting part.** Cloning one reference clip across
  all fifteen cuts would give the set a single consistent narrator instead of
  fourteen unrelated stock voices — which is the thing that would otherwise
  make multilingual narration feel cheaper than silence.
- Everything is local, so no script or recording leaves the machine.

### What to check before committing to it

- Whether the non-English output is good enough to ship. Telugu, Hindi, Greek
  and Ukrainian are the ones to audition first; a bad accent is worse than a
  caption.
- Timing. The captions are cut to fixed windows in `build-demo-videos`
  (`WINDOWS`), so narration has to fit those or the windows have to move.
- Whether the App Store previews should carry narration too, or stay silent.
  Previews autoplay muted, so the caption track is doing the work there and
  audio may not earn its keep.
- It is a large stack to install for an occasional asset build. Docker may be
  the cleaner way in than a native install.

---

## Key bar covers the bottom lines of the terminal

**Recorded:** 2026-08-29, reported from device with a screenshot.

With the keyboard up, the key bar is drawn **over** the last row or two of the
terminal instead of the terminal ending above it. In the report the Emacs mode
line was the last fully visible row, and another line was legible *through the
gaps between the key bar buttons* — which is the giveaway that the key bar is
an overlay on live terminal content, not a boundary the terminal was sized to.

Inside tmux this costs the tmux status line, since tmux draws it on the last
row.

### Why this is not the layout we intended

`TerminalHostView` (in `pockterm/Features/Terminal/SessionTabsView.swift`)
already pins the terminal to the keyboard:

```swift
terminalView.bottomAnchor.constraint(equalTo: container.keyboardLayoutGuide.topAnchor)
```

and its own doc comment says this exists so the terminal's bottom rows do not
end up "behind the accessory bar". So this is a fix that is incomplete or has
regressed, not a case nobody considered.

The key bar is the terminal's `inputAccessoryView`
(`TerminalSession.swift:70`), and `KeyBarView` is a self-sizing `UIInputView`
(`allowsSelfSizing = true`, intrinsic height 48).

### Suspects, in order

1. **`keyboardLayoutGuide` not counting the accessory view.** If the guide
   tracks the keyboard proper and not the self-sizing accessory above it, the
   terminal runs ~48 pt too low — which matches the one-to-two rows observed.
2. **The iOS 26 frame defect we already know about.** Reported keyboard frames
   exclude the predictive bar (~45 pt); see the auto-memory note on iOS 26
   keyboard avoidance. Same shape of error, similar magnitude.
3. **Timing.** The guide may resolve before the accessory self-sizes, leaving
   the constraint correct on paper and stale in practice.

### How to check it

Log `terminalView.frame.maxY` against the key bar's `frame.minY` in the
window's coordinate space while the keyboard is up: if the terminal's bottom is
below the bar's top, it is a layout bug and suspect 1 or 3. Then compare the
rows SwiftTerm reports (`proxy.onSize`) against the rows actually visible.

Worth answering early: does it reproduce **without tmux**, and does it happen
only when the keyboard is raised? Those two answers narrow it to a geometry
bug quickly.

### Measured 2026-09-15 — does NOT reproduce in the simulator

Checked on iPhone 17 / iOS 26 against main at `15cdace`, over a real SSH
session to the Mac's own sshd, by printing `LINE-1`..`LINE-60` and looking at
what the key bar covers. Probe kept as
`testKeyBarOcclusionGeometry` in the verify skill's driver.

**With the software keyboard up, there is no occlusion.** `LINE-60` and the
shell prompt below it are both fully visible, the key bar sits under them, and
nothing is legible through the gaps between the buttons. The key bar moves from
y=831 (docked) to y=523 (keyboard up) in an 874 pt window, so the layout does
respond to the keyboard. The constraint in `TerminalHostView` is doing its job
in this configuration.

**Do not measure this through XCUI frames.** `app.keyboards.firstMatch.frame`
reports minY 891 in an 874 pt window — the keyboard placed below the bottom of
the screen. That is the iOS 26 frame defect in the auto-memory note, and it
makes frame arithmetic here worthless. Printing numbered lines and reading the
screenshot is the measurement that works.

**There is no "keyboard down, key bar still showing" state on a touch-only
device.** The key bar is the terminal's `inputAccessoryView`, so dismissing the
keyboard resigns first responder and takes the bar with it. The docked bar seen
at launch in the simulator is its *hardware* keyboard — i.e. an external
keyboard on device.

So suspect 1 is not confirmed and suspect 3 is not visible here. What is still
untested, and where the report may yet live:

* **a physical device** — the original report came from one, with a screenshot;
* **tmux**, which draws its status line on the last row;
* **the docked/hardware-keyboard case** with a full screen of output, which this
  probe could not reach (typing raises the software keyboard, and hiding it
  removes the bar).

The report predates 1.5, 1.6 and 1.7, which included keyboard-avoidance work, so
"already fixed" is a live possibility alongside device- or tmux-specific. Do not
close it on this evidence alone; do not re-derive the simulator half either.

### Related

This is *occlusion*, distinct from the mode line **corruption** item below —
but both are about the bottom rows of the grid, so check whether one causes the
other before treating them separately.

---

## ~~Emacs mode line gets corrupted inside tmux~~ — ROOT-CAUSED AND FIXED 2026-09-18

**Recorded:** 2026-08-29. **Fixed:** 2026-09-18, after 1.7 shipped, which was
John's sequencing for it.

### It was a SwiftTerm bug, not ours

`Terminal.swift` in SwiftTerm 1.20.0 corrupts the screen when Insert Line or
Delete Line runs while **margin mode** (DECLRMM, `ESC [ ? 69 h`) is on. Both
`cmdInsertLines` and `cmdDeleteLines` walk the buffer from the **cursor row**
but count the **scroll region's full height**:

```swift
let rowCount = buffer.scrollBottom - buffer.scrollTop   // region height
let src = buffer.lines [row+i+1]                        // row = cursor row
```

With the cursor near the bottom that walks past the last line, and
`CircularList`'s subscript wraps modulo its backing array, so the tail of the
walk overwrites rows at the *top* of the screen. `cmdScrollUp`/`cmdScrollDown`
use the same idiom but start at `scrollTop`, so they are correct — only IL and
DL mismatch their start against their count. The fix is
`buffer.scrollBottom - buffer.y` in both, plus the vertical-region guard that
DL's margin branch is missing.

### Why it was tmux-only

Measured with the same harness, counting `ESC [ ? 69 h` in the byte stream:

| program | sends DECLRMM |
|---|---|
| emacs alone | 0 |
| vim alone | 0 |
| **tmux** (even running a bare `sh`) | **6** |

tmux enables margin mode at startup and never turns it off. That answers the
triage question this entry used to ask — it does **not** reproduce without
tmux, and now we know why rather than guessing.

### How it was measured

A headless harness ran SwiftTerm's emulator against a real pty running
`tmux` + `emacs`, using `tmux capture-pane` as the ground-truth oracle: any row
where the emulator disagrees with what tmux believes it drew is a defect. It is
deterministic (two runs byte-identical) and takes seconds.

* **Before:** 14 rows disagreed across a save/page scenario.
* **After:** 0.
* **Minimal case:** two byte streams differing only by `ESC [ ? 69 h` — margin
  off correct, margin on destroyed.
* **In the real app:** driven in the simulator over real SSH
  (`.claude/skills/verify`, `testTmuxEmacsModeLine`). Without the fix the app
  rendered a content line where the mode line belonged; with it, the screen
  matches `capture-pane` row for row.

### What shipped

An interim filter, `MarginModeFilter`, strips DECLRMM from the inbound stream
in `TerminalSession` so SwiftTerm never enters the broken path. tmux uses
margins only as a redraw optimisation and falls back to full repaints, so
declining the mode costs nothing visible — measured on the same live session.
The repair itself went upstream as
[migueldeicaza/SwiftTerm#707](https://github.com/migueldeicaza/SwiftTerm/pull/707)
— two lines plus the missing guard, with four regression tests, three of which
fail without it. **Remove the filter once a SwiftTerm release carries that.**
Check it at the next routine update, alongside Citadel #122:

```bash
gh pr view 707 --repo migueldeicaza/SwiftTerm --json state,mergedAt
```

### Still worth checking

This is a strong candidate for the **key bar occlusion** report above. That one
is also from inside tmux, also about losing the bottom row(s), and the
2026-09-15 probe already showed it is not a layout bug in the simulator. Before
spending anything more on it, re-test that report on a device against a build
carrying this fix.

### The original report, for the record

Running Emacs inside tmux, the mode line became garbled after actions that
redraw a lot: saving (`C-x C-s`) or moving around the buffer heavily.
Reproduced by John on device. The suspects listed here were scroll regions,
nested status lines, stale resize and the alternate screen; the actual cause
was none of them, which is why it was worth measuring rather than reasoning
about.

---

## Get off the Citadel dependency bottleneck (watch #122, then act)

**Recorded:** 2026-08-29 · **Reviewed:** 2026-09-06

Four of twelve dependencies are held, and every one is held by Citadel — see
the table in `CLAUDE.md`.

### Review 2026-09-06 — still dormant, and #122 is not the small change we assumed

Issue #122 is open with **zero comments and no activity since it was filed on
2026-01-08** — eight months. Citadel itself: 12 open PRs, last push 2026-06-12,
last release 0.12.1 on 2026-04-04. `CLAUDE.md` said to cost it out at this
review if it was still dormant, so here is the costing.

**The premise was wrong.** `#122` reads like a version bump and CI fix. It is
not. `Joannis/swift-nio-ssh`, the copy we build, carries a pluggable-algorithm
API that **Apple's library does not have**. Measured against Apple's own
0.15.0 source, not against code search:

| symbol | the fork we build | apple/swift-nio-ssh 0.15.0 |
|---|---|---|
| `NIOSSHAlgorithms` | 1 file | **absent** |
| `NIOSSHKeyExchangeAlgorithmProtocol` | 7 files | **absent** |
| `NIOSSHSignatureProtocol` | 3 files | **absent** |
| `NIOSSHPublicKeyProtocol` | used by Citadel | **absent** |
| `NIOSSHTransportProtection` | 12 files | 23 files (exists) |

Citadel registers three things through that API — AES128-CTR,
`diffie-hellman-group14-sha1`/`-sha256`, and `ssh-rsa` (`Insecure.RSA`). So
"migrate back to official swift-nio-ssh" means either **getting Apple to accept
a public algorithm-extension API first**, or **Citadel giving up RSA keys and
group14 key exchange**. Either way it is gated on a second upstream, which is
the likeliest reason the maintainer's own issue has sat untouched for eight
months.

**How far behind we are.** We are pinned to the 0.3.5 line. Apple shipped 0.4.0
on 2022-04-27 and is at **0.15.0 (2026-07-28)** — twelve minor releases.

**Coupling, if anyone still fancies forking Citadel:** 28 of its 43 source
files import NIOSSH, 116 symbol references, about 20 of them to API that does
not exist upstream.

### What the hold actually costs us — less than it looks

`SSHEngine.connect` calls `SSHClient.connect` **without an `algorithms:`
argument**, so it takes Citadel's default empty `SSHAlgorithms()` and registers
none of the extras. Nothing pockterm ships uses the API that the fork exists to
provide. (Side effect worth knowing separately: that also means we do not
support `ssh-rsa` keys or group14 key exchange, so older servers will refuse us.
That is a product question, not a dependency one.)

### Options, priced

1. **Read Apple's 0.4 → 0.15 release notes for client-affecting security and
   protocol fixes.** An afternoon. Since we use none of the pluggable
   algorithms, this is the only thing that decides whether the hold matters at
   all. **Do this one first** — it either produces a concrete reason to act or
   retires the anxiety with evidence.
2. **Contribute the migration upstream to Citadel.** No longer a small PR:
   blocked on new API in `apple/swift-nio-ssh` and their release cycle, or on
   dropping algorithms. Weeks, gated on two upstreams. Do not start this
   expecting it to unstick anything soon.
3. **Fork Citadel.** Inherits the same problem — the nio-ssh side is the hard
   part, not Citadel — so it buys nothing here. Still a real maintenance
   commitment; argue for it explicitly rather than drifting into it.
4. **Keep the holds.** Legitimate today and said out loud rather than by
   default: as of 2026-09-06 no advisory affects any of the 12 pinned versions
   (62 checked), and all four holds are understood and recorded.

**Recommendation: 1, then re-decide.** Nothing here is urgent.

---

## ~~Translate the app into the nine remaining languages~~ — DONE 2026-08-29

**Recorded:** 2026-08-15

Seven languages ship complete at **291/291 strings**: Spanish, Hebrew, Arabic,
Simplified Chinese, Traditional Chinese. Verify at any time with
`scripts/i18n-status`. (The catalogue grows: it was 274 when this was written,
301 keys today of which 291 translate. Re-check the count before estimating.)

**Found while verifying Italian:** the port-forward type picker
(`ForwardEditorView.swift:16`, `Text("Local")`) reads `Local` / `Remote` /
`Dynamic`, but `Local` is one of the ten `shouldTranslate: false` keys — so
every language shows a half-translated list, e.g. `Local / Remoto / Dinamico`.
It is almost certainly a mistake: `Local` happens to be correct Spanish, which
is likely how it got marked verbatim. Fixing it means un-flagging the key and
translating it for all seven languages; it is not Italian-specific, so it
belongs in its own change.

**All nine shipped on 2026-08-29**, one language per commit: Italian (#52),
French (#53), then Greek, Russian, Ukrainian, Japanese, Korean, Hindi and
Telugu (#56). The app now ships **14 languages** complete at 297/297 strings.

Notes worth keeping:

- **Russian and Ukrainian** use the four CLDR plural categories, as warned.
  Their tab labels also had to be shortened — `Связка ключей` and
  `Переспрямування` collided with their neighbours in a five-tab bar — so
  Keychain and Forwarding became `Ключи`/`Ключі` and `Порты`/`Порти`, and the
  guide sentences naming those tabs were realigned to the short labels.
- **Japanese and Korean** take only an `other` plural category.
- **Telugu shipped by John's decision** despite App Store Connect not offering
  it as a metadata locale, so the store listing cannot be localized to match.
- Verified by running each language in the simulator and reading the guide, not
  just by `i18n-status` — which reports the catalogue, not what is on screen.
  See the Local/`New Forward` defects found that way (#54).

Roughly 291 strings each, so about 2,600 translations in total. Ninety-seven of
them are full help-guide paragraphs rather than single words.

### Per language, the whole procedure

1. Add the code to `knownRegions` in `pockterm.xcodeproj/project.pbxproj`.
   Hyphenated codes need quoting.
2. Add the translations to `pockterm/Localizable.xcstrings`, keyed by the
   English source string.
3. Add that language's CLDR plural categories for `%lld sessions`.
4. `scripts/i18n-status` — must report the language complete with no format or
   markup problems.
5. Build, confirm the `.lproj` appears in the built app, and **run it**:
   `xcrun simctl launch <dev> John-Hancock.pockterm -AppleLanguages '(it)' -AppleLocale it_IT`
6. Commit.

Step 5 is not optional. Both bugs found so far — `Ungrouped` staying English,
and Arabic rendering the port as `٢٢` — were invisible in the catalog and
obvious in a screenshot.

### Things that will bite

- **Russian and Ukrainian need four CLDR plural categories** (`one`, `few`,
  `many`, `other`), the same treatment Arabic got with its six. A single string
  for `%lld sessions` is wrong in both.
- **Emphasis inside the help guide names UI controls.** Translate the word
  inside the `**` to whatever that control is called in that language, or the
  guide will tell the reader to tap a button that is not on their screen.
- **Do not translate the nine verbatim keys** — `..`, `•`,
  `user@host:~$ ls`, the format-only keys, `Terminal`, `OK`. They are
  already marked `shouldTranslate: false` and need no per-language action.
  (`Local` was a tenth until 2026-08-29; it was a port-forward type sitting
  next to a translated Remote and Dynamic, and being verbatim was a mistake.)
- **Telugu is worth confirming before spending the effort.** iOS supports it
  in-app, but App Store Connect does not offer it as a metadata locale, so the
  store listing cannot be localized to match.

Conventions, the terminal right-to-left rule and the Latin-digit rule are in
`docs/localization.md`. Nothing about them is language-specific, so no further
code changes should be needed for any of the nine.

---

## ~~Move both App Store URLs to pockterm.com, then take the repo private~~ — DONE 2026-08-29

Verified against the API and over HTTPS on 2026-08-29:

- Marketing URL and Support URL are `https://pockterm.com` in all seven locales.
- Privacy Policy URL is `https://pockterm.com/privacy.html` in all seven, and
  serves 200.
- The repo is PRIVATE, and staying private — open-sourcing is off the plan as
  of 2026-08-29. The old GitHub Pages privacy URL 404s, and nothing points at
  it any more.

The loose end below is closed: Hacker News was dropped altogether on
2026-08-29, so the submission-URL question it posed no longer exists.

**Recorded:** 2026-08-14

The repo is public again as a temporary measure. It should end up private — but
**the URL move has to ship first**, because the App Store currently depends on
GitHub for two links, and taking the repo private breaks both.

**Order matters. Do not flip private before a release carries the new URLs.**

### What breaks when the repo goes private

| App Store field | Currently points at | On going private |
|---|---|---|
| Marketing URL | `github.com/jhancock1975/pockterm` | 404 |
| Privacy Policy URL | `jhancock1975.github.io/pockterm/privacy.html` | 404 — GitHub Pages does not serve private repos on free plans |

Both were verified 404 while the repo was private on 2026-08-14. Note that
flipping back to public did **not** restore Pages — the privacy URL was still
404 afterwards, so Pages needs re-enabling in repo settings if it is ever relied
on again. Better not to rely on it.

### The replacement is already live

`pockterm.com` is up on S3 + CloudFront and serves both pages over HTTPS:

- `https://pockterm.com` — landing page, deliberately makes no mention of
  GitHub or open source, so it stays correct whether the repo is public or not
- `https://pockterm.com/privacy.html` — the privacy policy, recovered verbatim
  from `git show gh-pages:privacy.html`

Resource IDs and the redeploy command are in the auto-memory note
`pockterm-marketing-site`.

### Why this needs a release

Both fields are **frozen** while the app is live with no version in
`PREPARE_FOR_SUBMISSION`. The API returns HTTP 409 "cannot be edited at this
time" for `appStoreVersionLocalizations.marketingUrl` and
`appInfoLocalizations.privacyPolicyUrl`. This is a state lock, not a credentials
problem — `promotionalText` on the same record still writes fine (verified 200).

### Steps

1. Create the next version (1.4) in App Store Connect. It can be
   **metadata-only and reuse the existing VALID build** — no new binary needed.
2. Set `marketingUrl` to `https://pockterm.com` and `privacyPolicyUrl` to
   `https://pockterm.com/privacy.html`.
3. Carry the already-queued subtitle + keyword change in the same version — see
   `docs/discovery.md`. Keywords sit at **99 of 100 characters**, so terms must
   be swapped, not added.
4. **Re-provision the reviewer demo SSH host** and refresh the credentials in
   `docs/app-store-metadata.md`. The previous host was torn down on 2026-08-14
   after 1.3 was approved, and review will fail without a live one.
5. Submit, wait for approval, confirm both URLs resolve on the live listing.
6. **Only then** flip the repo to private.

### Loose end — closed

This asked whether to post to Hacker News before or after taking the repo
private. **Neither: Hacker News was dropped entirely on 2026-08-29** and the
draft was deleted. It is not planned and not on hold. Do not reconstruct the
question from this entry.

---

## ~~Terminal top bar is too crowded; AI icon collides with the close button~~ — DONE 2026-08-08

The active-session chip carries a red close button on its trailing edge, and the
AI Assistant sat immediately right of it: the icon row led with `Spacer()`, so AI
was the first *trailing* icon and landed hard against that red ✕.

**Fixed** by moving the AI button ahead of the `Spacer()`, onto the leading edge —
so the chip is centred with AI to its left and the remaining controls to its
right, and a frequently-tapped control no longer touches a destructive one.

Still open from the original note: with new-session, snippets, files, theme and
minimise all trailing, the bar will keep tightening. Some may belong behind an
overflow menu rather than each holding a top-level slot.

---

## ~~SwiftPM identity-conflict override for swift-nio-ssh is not future-proof~~ — RESOLVED 2026-08-29

**Took option 2: Citadel is pinned to exactly 0.12.0.** The identity conflict is
gone (SwiftPM reports zero "conflicting identity" warnings), so the
escalates-to-an-error problem no longer applies, and the third-party fork is
**not even fetched** any more — deleting its cached clone and re-resolving does
not bring it back. `Package.resolved`: `citadel 0.12.0`,
`swift-nio-ssh Joannis/swift-nio-ssh 0.3.5`.

The root `Joannis/swift-nio-ssh` declaration is kept deliberately. It no longer
overrides anything — 0.12.0 declares the same URL — but it states the source
explicitly rather than inheriting whatever Citadel decides, and it is what would
stop a future Citadel from quietly swapping the source again.

### What the pin cost — measured, not assumed

Nothing, as far as we use it:

- 0.12.1's only client-side change is **+57/-0 in `TTY/Client/TTY.swift`** —
  purely additive, adding `withExec`. `withPTY` and `executeCommand`, the two we
  call, have zero deletions. `withExec` is unused in the app.
- The stderr-flush fix is in `Exec/Server/ExecHandler.swift` — Citadel's SSH
  **server**. Pockterm is a client and never runs it.
- The remaining change is a Mac Catalyst build fix; we ship iOS.

Verified against the real thing, not just the diff: a temporary integration test
connected over SSH to the Mac's own sshd on Citadel 0.12.0 and ran the exact call
`SSHEngine.exec` makes.

| Case | Result on 0.12.0 |
|---|---|
| `( echo OUT; echo ERR >&2 ) 2>&1` | returned `OUT\nERR` — both streams |
| `( echo ONLYERR >&2 ) 2>&1` | returned `ONLYERR` — **the case claimed to hang** |
| `echo RAWERR >&2` (unmerged) | throws `TTYSTDError("RAWERR")`, as our code comment describes |

So `run_command` is unaffected, and the remote-subshell merge in `SSHEngine.exec`
remains necessary and correct.

**`scripts/routine_update.py` now guards this** — Citadel is in `CAPPED`, so the
check reports it as deliberately held instead of offering the bump. Do not take
Citadel 0.12.1+ without re-reading this entry; the bump silently puts a
zero-star account back in the dependency graph.

Still worth watching: Citadel issue #122, the maintainer's own plan to migrate
back to `apple/swift-nio-ssh`. That is the real fix, and it is upstream's to make.

---

### Original note

**Recorded:** 2026-08-08

Citadel 0.12.1 declares `Wellz26/swift-nio-ssh` — a zero-star third-party fork,
created and last pushed within the same 82 seconds. Citadel 0.10.0 through
0.12.0 all used the author's own `Joannis/swift-nio-ssh`; only 0.12.1 switched.

### What we actually build (verified 2026-08-29)

**We do not compile the fork.** The checkout in DerivedData is at
`791437a67f53`, which is `Joannis/swift-nio-ssh` 0.3.5 and matches the pin in
`Package.resolved`. The root override works.

**But the override is load-bearing, not cosmetic.** Wellz26 carries a **0.3.6**
tag (`a05e6bbe6b14`) that does not exist in Joannis's repo at all. Citadel asks
for `"0.3.4" ..< "0.4.0"`, so **0.3.6 is the highest match** — every Citadel
user without our override resolves to a commit that exists only in the zero-star
account. Ours resolves to Joannis 0.3.5 because we declare it at the root.

**The fork's content is not, on inspection, malicious.** Those 8 commits are
Joannis's own post-0.3.5 `main` (certificate-authentication work by `nedithgar`,
merged by Joannis himself) plus one commit by the fork owner: *"add NIO product
dependency to NIOSSH target for Mac Catalyst compatibility."* So it looks like a
Catalyst build fix that Citadel adopted wholesale instead of getting merged
upstream. The objection is the shape of the arrangement, not the diff.

**SwiftPM still clones the fork at resolve time** to read its manifest — there
is a bare `swift-nio-ssh-ccb6c93f` in `SourcePackages/repositories` pointing at
`Wellz26`. It is fetched and its `Package.swift` evaluated; it is just never
compiled.

**Upstream already wants out.** Citadel issue #122, *"Fix CI and migrate back to
official swift-nio-ssh"*, was opened by **Joannis, the maintainer**, on
2026-01-08 and is still open. Note the direction: back to `apple/swift-nio-ssh`,
not merely back to his own copy. Worth watching or nudging rather than filing a
new issue.

Also worth knowing: `Joannis/swift-nio-ssh` is not a GitHub fork of Apple's — it
is a separate 1-star repo created 2020-05-08. So even the "safe" side of this is
a personal copy of an Apple library, and `apple/swift-nio-ssh` (515 stars) is
still being pushed to as of 2026-07-28.

We now override it by declaring `Joannis/swift-nio-ssh` 0.3.5 at the root of
`pockterm.xcodeproj`, which wins the `swift-nio-ssh` identity. That works today,
but SwiftPM warns:

> Conflicting identity for swift-nio-ssh: ... This will be escalated to an error
> in future versions of SwiftPM.

So a future Xcode/SwiftPM will break the build. Options when that happens:

1. **Citadel moves back** to the author's fork upstream — best outcome; worth
   opening an issue on orlandos-nl/Citadel asking why 0.12.1 switched.
2. **Pin Citadel 0.12.0**, which declares Joannis's fork directly and needs no
   override — the fork would then never even be fetched.

   **The stated cost of this looks wrong (re-checked 2026-08-29).** The
   0.12.1 stderr-flush fix is in `Sources/Citadel/Exec/Server/ExecHandler.swift`
   — Citadel's SSH **server**. Pockterm is a client and never runs it. Our own
   `SSHEngine.exec` already merges the streams remotely with
   `executeCommand("( cmd ) 2>&1")`, in our source, independent of the Citadel
   version. `withExec` is unused — no references in the app. The other 0.12.1
   change is a Mac Catalyst build fix, and we ship iOS.

   So this may cost nothing. **Not yet tested** — verify by pinning 0.12.0,
   building, and exercising the assistant's `run_command` against a
   stderr-only command before believing it.
3. **Fork Citadel** under our own account with the dependency corrected.

### "Can we just use Apple's library instead of Citadel?" — no (checked 2026-08-29)

This was never Citadel *versus* Apple. **Citadel is built on top of
`swift-nio-ssh`** — it is the client layer Apple deliberately declined to
write. Dropping Citadel doesn't remove the Apple dependency, it just deletes
the layer in between. From Apple's own README:

> SwiftNIO SSH does not ship production-ready SSH clients and servers, but
> instead provides the building blocks [...] more like libssh2 than openssh.

**Apple has no SFTP at all** — searching the whole 0.15.0 source tree for
"sftp" returns nothing. SFTP is a separate subsystem protocol.

Nor did we ever switch to Citadel to work around Apple: Citadel arrives in the
first SSH commit (`c998ec9`), and `docs/superpowers/specs/2026-06-27-pockterm-design.md`
names the transport as "SwiftNIO SSH / Citadel" from the start.

What replacing it would cost: Citadel is 9,573 lines — SFTP 3,276, client layer
2,710, algorithms 1,576, TTY+Exec 939. Our four Citadel-facing files total 529.
That is protocol and crypto code in the security-critical path of an app whose
pitch is that keys never leave the device. libssh2-backed wrappers (Shout,
NMSSH, SwiftSH) are worse on the same terms: a memory-unsafe C library in the
security path, mostly unmaintained.

So the live options are the override we have, or pinning Citadel 0.12.0 —
**not** replacing Citadel.

Until then `scripts/routine-update` reports the pin as deliberately held.
