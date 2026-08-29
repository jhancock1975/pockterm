# Standing instructions for pockterm

Things that must survive across sessions. Short by design — everything else
lives in `docs/backlog.md`, `docs/dependency-policy.md`, or the skills.

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
| `swift-nio-ssh` 0.3.5 | Citadel's range caps below 0.4.0; also ~91 commits behind Apple |

One mid-sized library sits between us and four upstreams and decides which
versions we are allowed to have. #122 is the single change that would most
likely unstick that whole column.

**Baseline as of 2026-08-29 — do not assume it will resolve on its own.** The
issue is open with **zero comments and no activity since the day it was
filed**, and Citadel has 10+ open PRs sitting unmerged. Eight months of silence
from the maintainer on his own stated intent is the signal.

**So treat this as work we may have to do, not work to wait for.** If it is
still dormant at the next dependency review, cost out doing it ourselves and
put a real item in `docs/backlog.md`. Preference order:

1. **Contribute the migration upstream** as a PR to Citadel — everyone benefits
   and we carry no fork.
2. **Fork Citadel** under our own account only if upstream will not take it.
   This is a real maintenance commitment, not a shortcut; argue it explicitly.
3. Do nothing further, and keep the holds — legitimate, but say so out loud
   rather than by default.

Context and the measured detail are in `docs/backlog.md` under the resolved
SwiftPM identity-conflict entry.

## Dependency rules that do not bend

- **Never force a dependency past a constraint** by declaring it at the project
  root just to take a newer version. That is how the third-party fork nearly
  got in. See PRs #48 and #49 for the two times this was declined.
- **Every resolved package must come from a vetted source**, enforced by
  `scripts/routine-update` section 2. Full policy in `docs/dependency-policy.md`.
- **Do not bump Citadel to 0.12.1+** without re-reading the backlog entry. It
  reintroduces the fork.
