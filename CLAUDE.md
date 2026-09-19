# Standing instructions for pockterm

Things that must survive across sessions. Short by design — everything else
lives in `docs/backlog.md`, `docs/dependency-policy.md`, or the skills.

## Ship finished work without being asked

**Do not leave finished work sitting in the working tree, and do not ask
whether to land it.** The moment a change is verified — tests green, and built
or run if it is the sort of change that needs it — do the whole sequence
unprompted:

```bash
git checkout -b <branch>        # never commit straight to main
git commit                      # then push
gh pr create                    # a real description: why, what was measured
gh pr merge <n> --squash --delete-branch
git checkout main && git pull --ff-only
```

Finish with `git status` clean and `main` in sync. "Say the word and I'll open
a PR" is not a deliverable; John has had to ask for this too many times.

The only reasons to stop short of merging: tests are failing, the change is a
deliberate work-in-progress he has been told about, or he has said to hold it.
Say which one, rather than going quiet with a dirty tree.

## Watch Citadel issue #122, and start planning to fix it ourselves

**Check it whenever dependency work comes up** — a routine update, a Citadel
release, a new advisory:

```bash
gh api repos/orlandos-nl/Citadel/issues/122 --jq '{state, comments, updated_at}'
```

[orlandos-nl/Citadel#122](https://github.com/orlandos-nl/Citadel/issues/122),
*"Fix CI and migrate back to official swift-nio-ssh"*, was opened by Joannis —
Citadel's own maintainer — on 2026-01-08.

**Why it matters more than one issue normally would.** Four of our twelve
dependencies are held back, and *every one of them* is held by Citadel:

| Held | Because |
|---|---|
| `bigint` 5.7.0 | Citadel declares `from: "5.2.0"`, capping below 6.0.0 |
| `citadel` 0.12.0 | 0.12.1 declares a zero-star third-party `swift-nio-ssh` fork |
| `swift-crypto` 3.15.1 | Citadel pins `<4.0.0`; 4.0.0–4.3.0 carry GHSA-9m44-rr2w-ppp7 |
| `swift-nio-ssh` 0.3.5 | Citadel's range caps below 0.4.0; Apple is at 0.15.0 (twelve minor releases ahead) |

One mid-sized library sits between us and four upstreams and decides which
versions we are allowed to have.

**Costed out 2026-09-06 — #122 is not the small change it reads as, and it is
not ours to do.** Measured against Apple's own 0.15.0 source: the copy of
`swift-nio-ssh` we build carries a pluggable-algorithm API
(`NIOSSHAlgorithms`, `NIOSSHKeyExchangeAlgorithmProtocol`,
`NIOSSHSignatureProtocol`) that **Apple's library does not have**, and Citadel
registers `ssh-rsa`, `diffie-hellman-group14-*` and AES128-CTR through it.
Migrating back therefore needs new API accepted into `apple/swift-nio-ssh`
first, or Citadel dropping those algorithms. That is the likeliest reason the
maintainer's own issue has had zero comments since 2026-01-08.

**But pockterm uses none of it**: `SSHEngine.connect` passes no `algorithms:`,
so it takes Citadel's empty default. Before doing any of this work, read
Apple's 0.4 → 0.15 notes for client-affecting fixes — that is the only thing
that decides whether the hold matters. Full costing in `docs/backlog.md`.

**If it ever does become work we do**, preference order:

1. **Contribute the migration upstream** as a PR to Citadel — everyone benefits
   and we carry no fork.
2. **Fork Citadel** under our own account only if upstream will not take it.
   This is a real maintenance commitment, not a shortcut; argue it explicitly.
3. Do nothing further, and keep the holds — legitimate, but say so out loud
   rather than by default.

Context and the measured detail are in `docs/backlog.md` under the resolved
SwiftPM identity-conflict entry.

## Drop the DEC margin-mode filter when SwiftTerm #707 ships

`MarginModeFilter` strips DECLRMM (`ESC [ ? 69 h`) from the inbound stream
because SwiftTerm 1.20.0's Insert/Delete Line corrupt the screen in margin
mode — which is what garbled the emacs mode line inside tmux. It is a
**stopgap**, not the repair.

The repair is upstream as
[migueldeicaza/SwiftTerm#707](https://github.com/migueldeicaza/SwiftTerm/pull/707).
**Check it at every routine update**, next to Citadel #122:

```bash
gh pr view 707 --repo migueldeicaza/SwiftTerm --json state,mergedAt
```

Once a SwiftTerm release carries it: bump, delete `MarginModeFilter` and its
tests, restore the plain `feed` in `TerminalSession`, and re-run
`testTmuxEmacsModeLine` from the verify skill to confirm the screen still
matches `tmux capture-pane`. Full detail in `docs/backlog.md`.

## Dependency rules that do not bend

- **Never force a dependency past a constraint** by declaring it at the project
  root just to take a newer version. That is how the third-party fork nearly
  got in. See PRs #48 and #49 for the two times this was declined.
- **Every resolved package must come from a vetted source**, enforced by
  `scripts/routine-update` section 2. Full policy in `docs/dependency-policy.md`.
- **Do not bump Citadel to 0.12.1+** without re-reading the backlog entry. It
  reintroduces the fork.
