# Promotion notes

Working notes for promoting Pockterm. Credentials never belong here — the
demo-host password lives in `~/Documents/Apps/pockterm/demo-host.txt`, outside
the repo.

---

## 1. Show HN  ← ON HOLD (15 Aug 2026), keep the draft

Paused by decision, not by a blocker. The repo **stays public**, so this draft
still works exactly as written whenever it comes off hold — nothing here needs
rewriting.

**Submit at:** https://news.ycombinator.com/submit

**Title** (exact — HN strips editorialising, and "Show HN:" is the required prefix):

```
Show HN: Pockterm – a free SSH/SFTP client for iPhone
```

**URL** — the repo, *not* the App Store:

```
https://github.com/jhancock1975/pockterm
```

HN strongly prefers something you can read without an install. The repo is now
Apache-2.0 with a real README, so it stands on its own. An App Store link as the
submission URL reads as an ad and gets flagged.

**Then immediately post this as the first comment.** HN convention is that the
author explains in-thread; a Show HN with no author comment usually dies.

> I wrote this because none of the free iPhone terminals rendered full-screen
> console apps properly — vim, htop and tmux all came out garbled.
>
> It's native SwiftUI on top of SwiftTerm for emulation and Citadel for SSH.
> Keys live in the iOS Keychain, host keys are verified on first use and warn on
> change, and SFTP transfers stream in chunks so a large file doesn't blow up
> memory on a phone — that last one was a real bug: the first implementation
> read whole files into memory and would have been killed by the OS on anything
> sizeable.
>
> No account, no analytics, no ads, no subscription. There's an optional AI
> assistant that's off by default and needs your own API key — it tells you
> which provider is about to receive your terminal output before it sends
> anything.
>
> App Store: https://apps.apple.com/app/id6789968094
>
> Happy to answer anything about the SSH or terminal-emulation side.

**Timing:** Tuesday–Thursday, 08:00–10:00 US Eastern is the usual sweet spot.

**Afterwards:** stay in the thread for the first two hours. Replying to
questions matters more to ranking than the submission itself. Expect scrutiny of
the AI feature and the "free forever" claim — answer both plainly.

---

## 2. Reddit — a few days after HN

Post to **r/selfhosted** first, then **r/homelab**, then **r/commandline**,
spaced a few days apart. Never the same day.

**Read each sidebar first.** Self-promotion is restricted in all three; some
require a flair, some require an established comment history. Breaking the rule
gets you banned, not just removed.

**Title:**

```
I got tired of not being able to properly SSH into my homelab from my phone, so I built Pockterm
```

**Body:**

> Free, no account, no subscription, no ads. The thing that finally made me
> write it: every free iPhone terminal I tried mangled tmux and htop.
>
> - Full SFTP browser over the same connection
> - Ed25519/RSA keys stored in the iOS Keychain
> - Local and remote port forwarding
> - Host groups that pass credentials down, so a dozen boxes is one setup
> - Optional AI assistant, off by default, bring your own key
>
> App Store: https://apps.apple.com/app/id6789968094
> Source (Apache-2.0): https://github.com/jhancock1975/pockterm
>
> Happy to take feature requests.

Lead with the problem, not the feature list. That audience responds to "I had
this itch" far better than to a spec sheet.

---

## Why this order

Downloads have been flat at 26 since 4 August, all from the launch window. That
is a discovery problem, not a product one — no bad reviews, and 1.2 fixed a real
crash-class bug. ASO helps least on an app with no ranking signal, because Apple
has almost no engagement data to rank on. External traffic from where the
audience already gathers is the lever that actually moves it.

Don't wait for 1.3 to clear review. 1.2 is live and good; the 1.3 changes are
refinements nobody outside this repo is waiting on.

*(15 Aug: 1.3 is approved and live, so this no longer blocks anything — post.)*

---

## 3. App Store Connect — the parts only a human can do

Ordered by ceiling, not by effort. Nominations turn out to have an API
(`/v1/nominations`); the rest of this section genuinely has none.

**Featuring nomination.** App Store Connect → Pockterm → Featuring →
nominate. This is the one lever with a genuinely large payoff and no
programmatic path whatsoever. Apple's editors take unsolicited nominations
seriously for exactly this profile: native SwiftUI, no account, no analytics,
no subscription, and a real accessibility and localization story (five
languages including two RTL scripts, VoiceOver labels throughout). Nominations
hang off an upcoming release, so pair it with 1.4, and file it **at least three
weeks — ideally six — before** that release. Lead with the hook that isn't a
feature list: *the free iPhone terminals all mangle tmux and htop; this one
doesn't.*

### 3a. The nomination itself — drafted, awaiting a date

*(The form is at App Store Connect → Apps → Pockterm → sidebar → Featuring →
Nominations → **+** → Create Nomination. Role needed: Account Holder, which you
are. But there is also a `/v1/nominations` API — `POST` with
`submitted: false` creates the draft, so this can be filled in programmatically
and left for you to review and submit by hand.)*

**File early; the lead time is the runway, not a freeze.** `publishStartDate`
is a future date — the moment you want featuring around, i.e. 1.4's release —
and Apple asks for at least three weeks between filing and that date. Nothing
has to stop changing in between, and there is no minimum review count gating
any of it.

That three weeks is exactly when items 2 and 4 get done. Apple weighs seven
things; 1.4 is strong on five, and the two soft spots are both on the store
page — *Localization* is judged on the listing (en-US only today) and *App
Store product page* wants "compelling screenshots, app previews, and
descriptions, as well as positive ratings and reviews" (no video, no ratings
yet). Fix those during the runway rather than before filing. Nominations are
per-moment and unlimited, so filing for 1.4 costs nothing later.

- **Type:** `APP_ENHANCEMENTS` — the app launched in July, so not a launch.
- **Publish date:** target 1.4's release, ~22 Sep 2026.
- **File:** now.

**Name** (internal only): `Pockterm 1.4 — five languages, two of them RTL`

**Description:**

> Pockterm is a free, native SSH and SFTP client for iPhone — no account, no
> subscription, no ads, and no analytics of any kind.
>
> Version 1.4 is a localization and accessibility release. The app now ships
> complete in Spanish, Arabic, Hebrew, Simplified Chinese and Traditional
> Chinese — every string, including the entire in-app user guide and every
> VoiceOver label, not just the buttons. The right-to-left work went further
> than mirroring the layout: terminal content is deliberately never mirrored,
> because an SSH server addresses columns from the left whatever language the
> reader uses. Arabic and Hebrew users get a correctly mirrored interface
> wrapped around a correctly unmirrored terminal.
>
> The app exists because every free iPhone terminal we tried mangles
> full-screen console programs — vim, htop and tmux all render garbled.
> Pockterm renders them correctly, which is the entire point of carrying a
> terminal in your pocket.
>
> Also in the app: SFTP file browsing over the same connection; Ed25519 and RSA
> keys generated and held in the iOS Keychain; host-key verification that warns
> when a server's key changes; local and remote port forwarding; and host
> groups, so a dozen machines are one setup. An optional AI assistant is off by
> default, requires the user's own API key, and names the provider about to
> receive terminal output before anything is sent.
>
> Built in SwiftUI.

**Helpful details** (accessibility, inclusivity, priority):

> Accessibility: every control carries a localized VoiceOver label. Keyboard
> avoidance around the terminal is implemented by hand rather than with
> SwiftUI's automatic avoidance, which on iOS 26 leaves the bottom rows of the
> terminal hidden behind the predictive bar — the difference is largest for
> users running larger text.
>
> Inclusivity: five complete languages including two right-to-left scripts,
> with the terminal grid deliberately exempted from mirroring.
>
> This is our first featuring nomination.

**Supplemental materials** (up to 5 URLs) — all on pockterm.com, because the
repo goes private after approval and a nomination must not carry a link that
will 404 by the time an editor opens it:

- `https://pockterm.com/`
- `https://pockterm.com/ar.html` — the RTL page, which is the localization
  claim made visible without installing anything
- `https://pockterm.com/zh-Hans.html`
- `https://pockterm.com/privacy.html`
- the app preview video, once item 2 exists

---

**Record an app preview video.** The listing has four iPhone screenshots and no
video. Uploading is scriptable; recording is not. Fifteen to thirty seconds,
captured on the phone: connect → `htop` → `tmux` → drag a file through SFTP.
Two reasons it's worth the afternoon — editors effectively expect a preview
before they will consider featuring, and video moves conversion harder than any
keyword edit. 1080×1920, ≤30 s.

**Apple Search Ads account.** searchads.apple.com, same Apple ID, then a
payment method — I can't create an account or enter billing. Worth doing *as a
diagnostic, not a channel*: paid installs on a free app with no monetisation
are pure cost, but $5–10/day on exact-match `ssh client` / `sftp` for one week
answers the question the current numbers can't — whether the listing fails to
convert, or is simply never seen. Kill it once you have the answer.

**Custom product pages.** Up to 35 variants, each with its own screenshots and
its own URL. The API 404s for this key, so it is UI work. The payoff is
specific: give the Show HN link its own page whose first screenshot is tmux
rendering correctly, so the store page finishes the argument the post started.

---

## 4. Things I can do on request — say the word

- **Localise the listing.** The app speaks five languages; the store page is
  en-US only. Saudi Arabia is already the #3 country by downloads *against an
  English-only page*. Needs a 1.4 record open.
- **1.4 subtitle + keywords.** Planned in `docs/discovery.md`, was blocked on
  1.3 being in review — **1.3 is now live, so this is unblocked.**
- **Point Marketing URL at pockterm.com.** Both Support and Marketing currently
  aim at the GitHub repo; the site converts better. Rides with 1.4 (409s
  otherwise).
- **In-app review prompt.** There is no `requestReview` anywhere in the source.
  Nothing has ever asked a single user for a review, which is most of why there
  are none. Cheapest fix on this whole page.
- **Tear down the demo host** — 1.3 is approved, so it is now just an exposed
  EC2 box costing money.

---

## 1.4 store page — what has been applied (15 Aug 2026)

The 1.4 version record exists (`PREPARE_FOR_SUBMISSION`), which is what
unlocked the subtitle, keywords, marketing URL and new locales.

**English**

- Subtitle → `SSH, SFTP & terminal for Linux` (30/30), the change `docs/discovery.md`
  had queued for 1.4
- Keywords → the 100/100 set from that same plan
- Marketing URL → `https://pockterm.com` (was the GitHub repo, in both slots)
- Promotional text → restored; it comes back empty on every new version record
- Release notes → written, leading with the localization work

**Six new localizations** — es-ES, es-MX, ar-SA, he, zh-Hans, zh-Hant. Each has
its own description, keywords, promotional text, release notes and subtitle,
with terminology matched to `Localizable.xcstrings` so the listing and the app
agree. Every field inside Apple's limits.

**Screenshots.** Not a submission blocker: Apple falls back to "the next best
available language," so the new locales would have shown the English set. They
are being regenerated per language anyway, from the simulator over a live SSH
session — an editor opening the Arabic listing should see Arabic. The old set
also predates 1.4 and still shows the retired paintpalette icon.

**Found while doing this:** `Text(key.displayName)` in the key bar
customization screen took a plain `String`, which SwiftUI does not localize, so
"Tab / ← Left / Hide Keyboard" stayed English in every language.
`scripts/i18n-status` could not see it — it audits the catalog, not code
literals. Fixed, and the six strings are now translated.

---

## Current state (15 Aug 2026)

- **1.3 `READY_FOR_SALE`** — live, and the newest version
- 26 first-time downloads, 0 reviews, 12 countries (US 34, AU 5, SA 4 by units)
- Listing: en-US only, 4 × iPhone 6.7" screenshots, no preview video, no custom
  product pages, no in-app events
- Keywords already updated in 1.3 (99/100); subtitle still
  `Terminal, keys & AI assistant`, queued for 1.4
- Demo host re-provisioned for the 1.4 review (the 1.3 one had been torn down,
  so App Review had nothing to connect to). Address and password are in
  `~/Documents/Apps/pockterm/demo-host.txt`; tear it down once 1.4 is approved
  with `scripts/teardown-demo-host.sh`.
