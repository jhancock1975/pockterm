# Backlog

Things worth doing, not yet scheduled. Newest first.

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
