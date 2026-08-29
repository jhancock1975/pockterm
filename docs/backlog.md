# Backlog

Things worth doing, not yet scheduled. Newest first.

---

## Translate the app into the nine remaining languages

**Recorded:** 2026-08-15

Five languages ship complete at **291/291 strings**: Spanish, Hebrew, Arabic,
Simplified Chinese, Traditional Chinese. Verify at any time with
`scripts/i18n-status`. (The catalogue grows: it was 274 when this was written,
301 keys today of which 291 translate. Re-check the count before estimating.)

Nine remain, **one language per commit**, in this order:

1. Italian
2. French
3. Greek
4. Russian
5. Ukrainian
6. Japanese
7. Korean
8. Hindi
9. Telugu

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
- **Do not translate the ten verbatim keys** — `..`, `•`,
  `user@host:~$ ls`, the format-only keys, `Local`, `Terminal`, `OK`. They are
  already marked `shouldTranslate: false` and need no per-language action.
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

The loose end below is also resolved: `PROMOTION.local.md` no longer names the
repo as the Show HN submission URL — it now submits `pockterm.com`, with the
trade-off written up. The original note is kept below for the reasoning.

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

### Loose end

`PROMOTION.local.md` names the GitHub repo as the Show HN submission URL. Taking
the repo private kills that plan. Decide before the flip whether Show HN happens
first (repo public, as written), or whether the submission moves to
`pockterm.com` — HN treats marketing pages more harshly than source, so that is
a real trade-off, not a swap.

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
