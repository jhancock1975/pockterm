# Dependency policy

Pockterm is an SSH client. It holds users' server credentials and private keys,
so a hostile dependency would be about as bad as it gets. The npm failure mode —
`event-stream`, `colors`, `node-ipc` — is a package that was fine when adopted
and later changed hands, or quietly grew an obscure transitive dependency.

**Rule: every resolved package must come from a source a human has vetted.**

Enforced by `scripts/routine-update`, section 2. It is allowlist-based on
purpose. Heuristics like "lots of stars, recently updated" describe a hijacked
package just as well as a healthy one; the only durable question is whether
someone looked.

## Adding a dependency

Before adding to `TRUSTED_OWNERS` / `TRUSTED_REPOS` in
`scripts/routine_update.py`, answer all of these in the entry's comment:

1. **Who owns it?** A person or org with a reputation to lose, ideally reachable.
2. **How long has it existed, and is it still maintained?** Creation date and
   last push.
3. **Who actually commits?** One anonymous account is a different risk from a
   contributor base.
4. **If it is a fork — what does it change versus the parent?** Read the diff.
   Not the description, the diff.
5. **Does it need to exist at all?** The cheapest supply-chain fix is one fewer
   dependency.

Anything not on the list is reported and exits non-zero, even if it builds.

## Currently trusted

| Source | Why |
|---|---|
| `apple/*` | Apple official. 8 of our 12 packages. |
| `migueldeicaza/SwiftTerm` | Miguel de Icaza; 1.6k stars, active since 2019. The terminal emulator. |
| `attaswift/BigInt` | Károly Lőrentey; 815 stars, active since 2015. Pulled in by Citadel. |
| `orlandos-nl/Citadel` | Joannis Orlandos, Vapor core team; 380 stars, active since 2020. The SSH layer. |
| `Joannis/swift-nio-ssh` | The Citadel author's fork of Apple's. See below. |

## The one real exception: `Joannis/swift-nio-ssh`

Citadel cannot use `apple/swift-nio-ssh` directly — it implements an SSH
*server*, which needs APIs Apple keeps internal (public key serialization, a
public `sign` for server-side key exchange, multiple MACs per transport).

**Audited 2026-08-08.** It is a genuine fork of Apple's repo: the history is
Apple's, including 113 commits by Cory Benfield (SwiftNIO lead) and commits from
Johannes Weiss. The delta versus Apple is public-API surface, an AES-GCM crash
fix, version-string parsing tolerance, and platform support (visionOS, Android,
Musl). Contributors are identifiable. Nothing obfuscated, no build scripts, no
network calls added.

**But it forked from Apple on 2022-04-21 and is ~91 commits behind**, including
SSH hardening Apple shipped in 2026:

- `Limit client auth attempts (#247)`
- `Limit buffered state (#244)`
- `Configurable max packet size (#245)`
- `Fix readVersion() crash on bare LF as first byte (#238)`
- `Merge commit from fork` — GitHub's wording for a private security-advisory merge

**Assessed impact for this app:** most are hardening against a *hostile peer*.
Pockterm is a client connecting to servers the user chose, so the threat model is
a malicious or compromised server, and the realistic worst case is a crash or
resource exhaustion rather than credential disclosure. Real, but bounded — and
not a reason to ship an unaudited alternative.

**What would fix it properly**, in order of preference:

1. Citadel updates its fork against Apple's `main`. Worth asking upstream. This
   is not our fork to maintain.
2. Rebase Citadel's patch set onto current `apple/swift-nio-ssh` under an account
   we control. Removes the staleness, but then we own an SSH implementation.
3. Replace Citadel. Large, and Citadel itself is well-maintained.

Re-check this whenever Citadel releases. `scripts/routine-update` reports the pin
as deliberately held so it does not silently rot.

## Removed

`Wellz26/swift-nio-ssh` — a zero-star fork created and last pushed within the
same 82 seconds, declared by Citadel 0.12.1 (0.10.0–0.12.0 used the author's own
fork; only 0.12.1 switched). Its single commit was benign — one `Package.swift`
line for Mac Catalyst — but an anonymous account supplying an SSH client's
transport is not a dependency to accept by default. Overridden at the project
root; see `docs/backlog.md` for the SwiftPM caveat.
