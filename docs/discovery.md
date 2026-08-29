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

Expect the question anyway: a Show HN for a developer tool draws "is it open
source?" within the first few comments. Answer it plainly rather than dodging —
the app is free, there is no backend and no telemetry, and the source is simply
not published at the moment. A straight no reads far better there than silence
or a maybe.

## Launch post drafts

Both are drafts to post yourself. Most communities treat self-promotion by a
third party poorly, and several ban it outright.

### Show HN

> **Show HN: Pockterm – a free SSH/SFTP client for iPhone**
>
> I wrote this because none of the free iPhone terminals rendered full-screen
> console apps properly — vim, htop and tmux all came out garbled.
>
> It's native SwiftUI on top of SwiftTerm for emulation and Citadel for SSH.
> Keys live in the iOS Keychain, host keys are verified on first use and warn on
> change, and SFTP transfers stream in chunks so a large file doesn't blow up
> memory on a phone.
>
> No account, no analytics, no ads, no subscription. There's an optional AI
> assistant that's off by default and needs your own API key — it tells you which
> provider is about to receive your terminal output before it sends anything.
>
> Happy to answer anything about the SSH or terminal-emulation side.

HN responds to the engineering, not the pitch — the memory-streaming detail and
the host-key handling are more interesting there than the feature list.

### r/selfhosted, r/homelab

> **I got tired of not being able to properly SSH into my homelab from my phone,
> so I built Pockterm**
>
> Free, no account, no subscription, no ads. The thing that finally made me write
> it: every free iPhone terminal I tried mangled tmux and htop.
>
> - Full SFTP browser over the same connection
> - Ed25519/RSA keys stored in the iOS Keychain
> - Local and remote port forwarding
> - Host groups that pass credentials down, so a dozen boxes is one setup
> - Optional AI assistant, off by default, bring your own key
>
> [App Store link] — happy to take feature requests.

Check each subreddit's self-promotion rule first; some require a flair, some
require you to be an established commenter.

### r/SideProject

That sub is builders, not sysadmins, so the SSH feature list means nothing to
most of them. Lead with the problem and the numbers; they reward honesty about
small numbers far more than they reward a pitch.

Title (pick one):

> I built a free SSH client for iPhone because every other one mangled vim.
> 28 users in five weeks.

> Six releases in five weeks, 28 users, zero revenue by design. Here's what I
> built and what I got wrong.

Body:

> **What it is:** Pockterm, a free SSH and SFTP client for iPhone. Native
> SwiftUI. No account, no tracking, no ads, no subscription, no paid tier.
>
> **Why I built it:** I wanted to fix a server from my phone while away from my
> desk. Every free iPhone terminal I tried mangled full-screen console programs
> — vim, htop and tmux all came out garbled, because they don't implement enough
> of the terminal to redraw a screen properly. So I wrote one that does.
>
> **The stack:** SwiftUI, SwiftTerm for terminal emulation, Citadel for the SSH
> layer. Keys are generated on device and stored in the iOS Keychain. Host keys
> are pinned on first connection and you get warned if one ever changes. SFTP
> runs over the same connection and streams in chunks, so pulling a large file
> doesn't blow up memory on a phone.
>
> **Numbers, since you'll ask:** shipped 11 July. 28 first-time downloads across
> 12 countries. Zero ratings. Six releases in five weeks. New installs have been
> flat for two weeks, which is the actual problem — the app works, nobody knows
> it exists.
>
> **The thing I underestimated:** localization. It ships in six languages, two
> of them right-to-left, and Arabic and Hebrew turned out to be much harder than
> translating strings. You mirror the entire interface, but you must *not*
> mirror the terminal itself — an SSH server addresses column 1 on the left no
> matter what language you read in, so a mirrored grid renders every full-screen
> program backwards. The fix is a mirrored UI wrapped around an unmirrored
> terminal, which is not a thing any framework does for you.
>
> **What I'd like feedback on:** how you'd find an app like this if you needed
> it. I think the honest answer is that developer tools don't get discovered on
> the App Store, and I don't have a distribution channel. Curious what worked
> for anyone here who shipped a free tool.
>
> [App Store link]

Then answer the inevitable monetization question in a comment rather than
pre-empting it in the post — pre-empting reads defensively:

> No plans to charge. It costs me $99 a year for the developer account and
> nothing to run — there is no backend, so users cost me nothing. There's an
> optional AI assistant that takes your own API key; I don't resell tokens and
> don't want to be in the billing business. If it ever needs money I'd rather
> ask than paywall it.

## Honest expectation

ASO helps at the margin, and it helps *least* on an app with no ranking signal —
Apple has almost no engagement data to rank 26 downloads on. The keyword work is
free and worth doing, but the thing that actually moves this is external traffic
from somewhere the audience already gathers. The README and the launch posts
matter more than the keyword field.
