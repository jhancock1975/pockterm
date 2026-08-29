# Discovery notes

Downloads: 26 first-time, all from the 21–25 Jul launch window, flat since 4 Aug.
Nothing about 1.2 will change that on its own — the listing has to be *found*.
This file records what was changed, what is staged, and what is still a decision.

## Done

**README, repo description, topics.** The App Store listing's Developer Website
*and* Support URL used to point at the GitHub repo, which had no README, no
description and no topics — every person who tapped through landed on a bare
file tree. Both fields now point at pockterm.com in all seven locales
(verified against the API 2026-08-29), which is the right target anyway now
that the repo is staying private.

**Promotional text restored.** It was set on 1.1 but came back empty on 1.2 —
creating a version does not carry it across. It shows above the description and
is the one metadata field editable on a live version without review, so it is
worth keeping filled.

## Shipped in 1.3

Keywords, applied when the 1.3 version record unlocked them (99/100):

```
ssh,sftp,shell,console,server,linux,vps,raspberry,pi,tunnel,port,forward,scp,ftp,remote,client,bash
```

Subtitle left at `Terminal, keys & AI assistant`. It could not be changed while
1.3 was in review — the app-info record returns `409` — and changing it would
have meant cancelling the submission and losing the queue position. Deferred to
1.4 deliberately; see below.

## Staged for 1.4

Keywords cannot be edited on a shipped version — the API returns
`409 STATE_ERROR`. They unlock when a new version enters
`PREPARE_FOR_SUBMISSION`, so these ride along with 1.3.

**Current** (88/100):

```
ssh,sftp,terminal,shell,console,server,port forward,tunnel,ssh client,devops,sysadmin,ai
```

**Proposed** (99/100):

```
ssh,sftp,shell,console,server,linux,vps,raspberry,pi,tunnel,port,forward,scp,ftp,remote,client,bash
```

Reasoning:

- Apple indexes **app name + subtitle + keywords as one pool** and recombines
  tokens across them. `terminal` and `ai` are already in the subtitle
  ("Terminal, keys & AI assistant"), so spending keyword characters on them buys
  nothing. Same for the space in `port forward` and the redundant `ssh client` —
  `port`,`forward`,`ssh`,`client` recombine into both.
- That freed room for the terms this app's actual users search:
  **linux, vps, raspberry, pi, scp, ftp, remote, bash**. "SSH from my phone to a
  Raspberry Pi / VPS" is the archetypal use case and none of it was indexed.
- Dropped `devops` and `sysadmin`: role words, searched far less than the thing
  being administered.
- No competitor names. Apple rejects metadata containing them, and it is not
  worth a rejection.

### Subtitle and keywords must change together

Decided: move to `SSH, SFTP & terminal for Linux` (30/30) in 1.4. The subtitle
carries more ranking weight than the keyword field, so the highest-volume terms
belong there. It costs the "AI assistant" hook, which helped conversion once
someone was already on the page.

**These two fields are coupled and must be edited in the same submission.**
Apple indexes name + subtitle + keywords as one pool, so the moment the subtitle
starts carrying `ssh`, `sftp`, `terminal` and `linux`, paying for any of them in
the keyword field is waste.

Dropping `ssh`, `sftp` and `linux` frees 15 characters, plus the 1 unused:

```
shell,console,server,vps,raspberry,pi,tunnel,port,forward,scp,ftp,remote,client,bash,key,homelab,nas
```

100/100. `key` returns because `keys` leaves the subtitle; `homelab` and `nas`
are where this app's users actually gather.

**Timing note:** the subtitle lives on `appInfoLocalizations`, not on the
version, and is only editable while no version is in review. Set it *before*
submitting 1.4, not after.

## Licensing — settled

**Apache License 2.0** (`LICENSE`, with third-party attribution in `NOTICE`).
Every dependency is compatible: nine are Apache-2.0 already — all the Apple
packages plus swift-nio-ssh — and SwiftTerm, Citadel and BigInt are MIT, which
combines cleanly. Apache-2.0 also carries an explicit patent grant, which MIT
does not.

**The repo stays private for now** (decided 2026-08-29). The Apache-2.0 LICENSE
and NOTICE still matter — they settle the third-party attribution the
dependencies require — but nothing published should offer, imply, or link
source. The drafts below are written accordingly.

If the question ever comes up in public, answer it plainly rather than dodging:
the app is free, there is no backend and no telemetry, and the source is simply
not published at the moment. A straight no reads better than a maybe.

## STOP — BEFORE ANYTHING GOES ON REDDIT, GO EARN SOME KARMA

**Do not post about Pockterm on Reddit. Not a submission, not a comment, not a
megathread, not "just asking for feedback on my side project". Not yet.**

The account is old but has **never posted anything**. A first-ever submission
that links your own app is the exact shape every spam filter is tuned for. And
removals are *silent* — the post looks completely normal to you while nobody
else can see it, so you will think it flopped when it was never shown.

**The task, and it is a boring one: go be a normal Reddit user for two or three
weeks first.** Comment where there is actual expertise to offer —
r/iOSProgramming, r/commandline, r/selfhosted. SwiftUI, iOS 26 keyboard
avoidance, String Catalogs, App Store rejections, RTL layout, terminal
emulation. Answer other people's questions. Link nothing.

Non-negotiables:

- **These have to be your own comments.** Do not have me write them. Post copy
  is marketing; a comment history has to read like a person, and a fake one
  reads exactly like what it is.
- **Never buy karma and never use an alt.** Vote manipulation gets both the
  account and the thing being promoted banned.
- **Read each sub's rules from a logged-in browser** before posting there. Some
  are login-gated and cannot be checked any other way.

**Only once there is a real comment history does Pockterm get mentioned on
Reddit at all.** Until then, this is the entire Reddit plan, and this section
stays pinned at the top of the file until it is honestly done.

*Hacker News: dropped 2026-08-29. Not planned, not on hold. Don't re-draft it.*

## Honest expectation

ASO helps at the margin, and it helps *least* on an app with no ranking signal —
Apple has almost no engagement data to rank 26 downloads on. The keyword work is
free and worth doing, but the thing that actually moves this is external traffic
from somewhere the audience already gathers — which, with Hacker News dropped and
Reddit gated behind building a comment history first, Pockterm does not currently
have. That is the real gap, not the keyword field.
