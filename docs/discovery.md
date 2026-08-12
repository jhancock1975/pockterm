# Discovery notes

Downloads: 26 first-time, all from the 21–25 Jul launch window, flat since 4 Aug.
Nothing about 1.2 will change that on its own — the listing has to be *found*.
This file records what was changed, what is staged, and what is still a decision.

## Done

**README, repo description, topics.** The App Store listing's Developer Website
*and* Support URL both point at the GitHub repo, which had no README, no
description and no topics — every person who tapped through landed on a bare
file tree. That was the largest leak and it is now fixed.

**Promotional text restored.** It was set on 1.1 but came back empty on 1.2 —
creating a version does not carry it across. It shows above the description and
is the one metadata field editable on a live version without review, so it is
worth keeping filled.

## Staged for the next submission

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

### Subtitle — a decision, not a recommendation

Currently `Terminal, keys & AI assistant` (29/30). The subtitle carries more
ranking weight than the keyword field, so it is worth deciding deliberately:

| Option | Trades |
|---|---|
| Keep as-is | "AI assistant" is a genuine differentiator and helps *conversion* once someone is on the page. |
| `SSH, SFTP & terminal for Linux` (30/30) | Maximum search weight — puts the four highest-volume terms in the strongest field. Loses the AI hook. |

Ranking versus conversion. Not obviously one or the other.

## Licensing — settled

**Apache License 2.0** (`LICENSE`, with third-party attribution in `NOTICE`).
Every dependency is compatible: nine are Apache-2.0 already — all the Apple
packages plus swift-nio-ssh — and SwiftTerm, Citadel and BigInt are MIT, which
combines cleanly. Apache-2.0 also carries an explicit patent grant, which MIT
does not.

This matters for a Show HN: the repo is now genuinely open source rather than
merely public, so "source is at ..." is an invitation instead of a technicality.

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
> Source is at github.com/jhancock1975/pockterm. Happy to answer anything about
> the SSH or terminal-emulation side.

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
> [App Store link] — source at github.com/jhancock1975/pockterm. Happy to take
> feature requests.

Check each subreddit's self-promotion rule first; some require a flair, some
require you to be an established commenter.

## Honest expectation

ASO helps at the margin, and it helps *least* on an app with no ranking signal —
Apple has almost no engagement data to rank 26 downloads on. The keyword work is
free and worth doing, but the thing that actually moves this is external traffic
from somewhere the audience already gathers. The README and the launch posts
matter more than the keyword field.
