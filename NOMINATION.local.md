# Pockterm featuring nomination

**Already filed as a draft in App Store Connect** — id `eff686ec-7ace-4966-8773-78def566a8e0`, state
`DRAFT`, nothing sent to Apple. Submitting is one flag
(`submitted: true`) on `PATCH /v1/nominations/eff686ec-7ace-4966-8773-78def566a8e0`, or the Submit button
under Apps → Pockterm → Featuring → Nominations.

This file is generated from the filed draft, so it cannot drift from it.

## Field limits

Apple documents none of these. Probed against the API by sending oversized
values and reading the rejection:

| Field | Limit | Filed |
|---|---|---|
| Nomination Name | 60 | 48 |
| Description | 1000 | 1000 |
| Helpful Details (`notes`) | 500 | 434 |
| Supplemental URLs | 5 | 5 |

## Name

```
Pockterm 1.4 — five languages, two right-to-left
```

## Type

```
APP_ENHANCEMENTS
```

## Publish date

```
2026-09-15T11:00:00Z
```

Chosen when a later release was assumed. 1.4 now ships on approval, so pull
this earlier if you want the featuring date to track the release.

## Description (1000/1000)

```
Pockterm is a free, native SSH and SFTP client for iPhone: no account, no subscription, no ads, no analytics.

Version 1.4 is a localization and accessibility release. It now ships complete in Spanish, Arabic, Hebrew, Simplified Chinese and Traditional Chinese: every string, including the whole in-app user guide and every VoiceOver label. The right-to-left work went past mirroring the layout — terminal content is never mirrored, because an SSH server addresses its columns from the left whatever language the reader uses. Arabic and Hebrew users get a mirrored interface wrapped around an unmirrored terminal.

It exists because every free iPhone terminal we tried mangles full-screen console programs: vim, htop and tmux render garbled. Pockterm doesn't.

Also: SFTP over the same connection, keys held in the iOS Keychain, host-key change warnings, port forwarding. The optional AI assistant is off by default and needs the user's own API key.

Built in SwiftUI. Source public under Apache-2.0.
```

## Helpful Details (434/500)

```
Accessibility: every control carries a localized VoiceOver label. Keyboard avoidance around the terminal is implemented by hand, because SwiftUI's automatic avoidance on iOS 26 leaves the terminal's bottom rows behind the predictive bar — worst for anyone running larger text.

Inclusivity: five complete languages, two of them right-to-left, with the terminal grid deliberately exempt from mirroring.

Our first featuring nomination.
```

## Supplemental materials

```
https://pockterm.com/zh-Hans.html
https://pockterm.com/ar.html
https://pockterm.com/
https://github.com/jhancock1975/pockterm
https://apps.apple.com/app/id6789968094
```
