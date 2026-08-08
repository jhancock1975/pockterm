# Backlog

Things worth doing, not yet scheduled. Newest first.

---

## Terminal top bar is too crowded; AI icon collides with the close button

**Reported:** 2026-08-08 (on device, iPhone 17 Pro Max)

The active-session chip carries a red close button on its trailing edge, and the
AI Assistant (sparkles) sits immediately to its right in the same icon row. At
the default size the two visually collide — the sparkles appear to overlap the
close button, and it is easy to hit the wrong one. The row is
`[session chip ✕] ✨ + 📁 🎨 ⌄` — six targets competing for one line.

**Wanted:** move the AI Assistant icon to the **left** of the session-name /
close-connection chip, so the destructive close control is not adjacent to a
frequently-tapped one.

**Where:** `pockterm/Features/Terminal/SessionTabsView.swift` — `topBar`, the
`HStack` after `activeSessionChip(active)`. The AI button is the first item in
that trailing `HStack`; the close button lives inside the chip itself.

**Worth considering while in there:** with Files, Theme, Snippets, New Session,
Minimise and AI all on one row, the bar will keep getting tighter. Some of these
may belong behind an overflow menu rather than each having a top-level slot.

---

## SwiftPM identity-conflict override for swift-nio-ssh is not future-proof

**Recorded:** 2026-08-08

Citadel 0.12.1 declares `Wellz26/swift-nio-ssh` — a zero-star third-party fork,
created and last pushed within the same 82 seconds. Citadel 0.10.0 through
0.12.0 all used the author's own `Joannis/swift-nio-ssh`; only 0.12.1 switched.

We now override it by declaring `Joannis/swift-nio-ssh` 0.3.5 at the root of
`pockterm.xcodeproj`, which wins the `swift-nio-ssh` identity. That works today,
but SwiftPM warns:

> Conflicting identity for swift-nio-ssh: ... This will be escalated to an error
> in future versions of SwiftPM.

So a future Xcode/SwiftPM will break the build. Options when that happens:

1. **Citadel moves back** to the author's fork upstream — best outcome; worth
   opening an issue on orlandos-nl/Citadel asking why 0.12.1 switched.
2. **Pin Citadel 0.12.0**, which declares Joannis's fork directly and needs no
   override. Costs the 0.12.1 stderr-flush fix (stderr-only output hangs
   `exec`, which the AI assistant's `run_command` uses) and `withExec`.
3. **Fork Citadel** under our own account with the dependency corrected.

Until then `scripts/routine-update` reports the pin as deliberately held.
