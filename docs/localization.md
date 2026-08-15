# Localization

Pockterm ships English plus Spanish, Hebrew, Arabic, Simplified Chinese and
Traditional Chinese. This document covers how strings get into the app, the
rules that are specific to a *terminal* rather than an ordinary app, and how to
add the next language.

## Where strings live

All UI strings live in a single Xcode String Catalog: `pockterm/Localizable.xcstrings`.

There is no `Localizable.strings` to hand-edit. The catalog is JSON, keyed by
the English source string, and Xcode compiles it into per-language `.lproj`
bundles at build time.

Most strings need no code change to be localizable. SwiftUI treats the first
literal argument of `Text`, `Button`, `Label`, `Section`, `TextField`,
`Picker`, `Toggle`, `navigationTitle` and friends as a `LocalizedStringKey`, so
`Text("Hosts")` is already looked up in the catalog.

A `String` variable is **not** looked up. `Text(someString)` renders verbatim.
When a value is UI text rather than user data, localize it where it is built:

```swift
// HostsListView.sections — the other section titles are user-entered group
// names and must stay verbatim, so only this one is localized.
result.append((title: String(localized: "Ungrouped"), hosts: ungrouped))
```

## Never hand-write the catalog keys

Keys must match exactly what SwiftUI looks up at runtime, and interpolation
makes that non-obvious. `Text("Active on :\(port)")` does not look up
`"Active on :\(port)"` — it looks up a key with a format specifier substituted,
whose spelling depends on the interpolated type:

| Source | Actual catalog key |
|---|---|
| `Text("Active on :\(port)")` where `port` is `Int` | `Active on :%lld` |
| `Text("Active on :\(port.technicalDigits)")` (a `String`) | `Active on :%@` |
| `Text("\(user)@\(address):\(port)")` | `%@@%@:%lld` |

A key that does not match **fails silently** — the app shows English, with no
warning at build or run time. So the keys are extracted from the build rather
than typed by hand:

```bash
xcodebuild build -project pockterm.xcodeproj -scheme pockterm \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -derivedDataPath build/dd-i18n
# every key Xcode extracted, with correct format specifiers:
find build/dd-i18n -path '*pockterm.build*' -name '*.stringsdata'
```

Each `.stringsdata` is JSON: `tables.Localizable[].key`. Note that changing an
interpolated value's type changes the key, and the old translation is then
orphaned — that is exactly what happened when ports moved to `technicalDigits`.

## Right-to-left: the terminal never mirrors

In Hebrew and Arabic iOS mirrors the interface, and Pockterm lets that happen
for chrome — navigation, lists, tab bar, settings. Verified in the simulator:
the tab bar reverses and titles right-align.

The terminal is different, and every established emulator agrees — xterm,
iTerm2, GNOME Terminal and Windows Terminal all render the cell grid
left-to-right regardless of UI language. The reason is structural. A terminal
is a matrix of character cells addressed by column, and the escape sequences
the server sends count columns from the left. Mirror the grid and column 0
lands on the right, so every cursor-addressed program — `vim`, `htop`, `tmux` —
draws backwards. The server has no idea the client is running in Arabic.

Three places enforce this:

| Surface | Mechanism | Why |
|---|---|---|
| `TerminalHostView` | `pinLeftToRightForTerminalContent()` on the container and every descendant | SwiftTerm is UIKit and resolves its own drawing against `semanticContentAttribute`, which the SwiftUI environment does not reach. Re-applied in `updateUIView` so subviews SwiftTerm adds later are covered. |
| `KeyBarView` | `semanticContentAttribute = .forceLeftToRight` | Arrow keys must keep pointing where they send; key order matches a physical keyboard; the dismiss pad is positioned on the trailing edge and would jump sides. |
| Technical values | `.forcesLeftToRight()` | Hostnames, ports, paths and commands are LTR content. `/var/log/syslog` in a mirrored field puts the leading slash on the right. |

The helpers are in `pockterm/Localization/LeftToRight.swift`.

This is about *layout direction*, not bidirectional text. If a server sends
Hebrew or Arabic, Pockterm displays whatever is in those cells and does not
attempt bidi reordering inside the grid — also the norm for terminal emulators.

## Digits in technical values

An integer interpolated into a `LocalizedStringKey` is formatted for the user's
locale. In Arabic, `22` renders as `٢٢`.

For a **count** that is correct, and those sites keep locale formatting —
"3 sessions", "12 selected", a font size in points.

For an **identifier** it is wrong. A port or an octal permission mask has to
match what the user put in a config file on the server, and `٢٢` does not read
as `22` when checking against `sshd_config`. Use `technicalDigits`
(`pockterm/Localization/TechnicalDigits.swift`):

```swift
Text("\(user)@\(host.address):\(eff.port.technicalDigits)")
```

## Strings that must not be translated

Ten keys are marked `"shouldTranslate": false` so they survive verbatim in
every language, and are excluded from the compiled `.lproj`:

- `..` — the parent-directory row in the file browser
- `•` — a separator
- `user@host:~$ ls` — a shell example, which must stay a valid command
- `%@: %@`, `%@:%@\n%@`, `%@@%@`, `%@@%@:%@` — format-only, no prose
- `Local`, `Terminal`, `OK` — identical across the shipped languages

## Plurals

`%lld sessions` carries per-language plural variations, not one string. CLDR
categories differ:

| Language | Categories |
|---|---|
| English, Spanish | `one`, `other` |
| Hebrew | `one`, `two`, `many`, `other` |
| Arabic | `zero`, `one`, `two`, `few`, `many`, `other` |
| Chinese (both) | `other` only |

Every form keeps its `%lld` so a count can never go missing. These compile to a
real `.stringsdict`; confirm with
`plutil -p <App>.app/ar.lproj/Localizable.stringsdict`.

## Adding a language

1. Add the code to `knownRegions` in `pockterm.xcodeproj/project.pbxproj`.
   Hyphenated codes need quoting: `"zh-Hans"`.
2. Add a translation table keyed by the English source string.
3. Add the language's CLDR plural categories for `%lld sessions`.
4. Rebuild, then confirm the `.lproj` appears in the built app.
5. Run it: `xcrun simctl launch <dev> John-Hancock.pockterm -AppleLanguages '(xx)' -AppleLocale xx_XX`

Step 5 is not optional. Both bugs found during this work — `Ungrouped` staying
English, and the Arabic-Indic port digits — were invisible in the catalog and
obvious in a screenshot.

## Checking coverage

`scripts/i18n-status` reads the catalog and reports per-language coverage plus
the two defects that ship looking fine — a dropped format specifier, and an
unbalanced `**` or backtick pair that renders as literal punctuation in the
guide. `scripts/i18n-status --missing fr` lists what one language still needs.

Run it before committing a language. It needs no build and no network.

## Known gaps

- **Nine languages remain**: French, Japanese, Korean, Russian, Ukrainian,
  Hindi, Telugu, Greek, Italian. Everything they need is in place — the
  extraction, the RTL rules and the digit rules are language-agnostic — so
  what is left is translation volume. See `docs/backlog.md`.
- **App Store metadata** — the listing description and keywords are separate
  from the app's own strings and are not localized. That is what surfaces the
  app in a local App Store's search, so for discovery it may matter more than
  the UI does. It is also gated on the same version lock as the marketing URL.

Everything else that was outstanding is now done: the help guide is extracted
and translated, both `LocalizedError` types are localized, and `VoiceOver`
reads translated labels (fifteen of the sixteen `accessibilityLabel` sites had
always passed literals, so only `HostProtocol.title` needed changing).
