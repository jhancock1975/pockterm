# Publishing pockterm to the Apple App Store

A concrete runbook for shipping pockterm (SSH/SFTP client + AI assistant) to the App Store,
mapped to Apple's App Review Guidelines. Items are split into **repo changes** (done in code),
**your Apple-account actions** (only you can do these), and **decisions** (calls only you should make).

Current project facts (as of writing):
- Bundle ID: `John-Hancock.pockterm`
- Team ID: `5H22F8M69N`
- `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1`
- `IPHONEOS_DEPLOYMENT_TARGET = 26.5`
- `GENERATE_INFOPLIST_FILE = YES` (Info.plist is synthesized from build settings)
- Device family `1,2` (iPhone + iPad)

---

## 0. Decisions to make first

### 0a. Deployment target (iOS 26.5) — HIGH IMPACT
iOS 26.5-only means a near-zero installed base. For a real public release, lower
`IPHONEOS_DEPLOYMENT_TARGET`. Blocker: pockterm uses iOS 26 APIs (Liquid Glass,
`tabViewBottomAccessory`, manual keyboard avoidance tied to iOS 26 behavior). Lowering
requires `#available` guards or fallbacks for those. If this is a personal / TestFlight-only
release, keeping 26.5 is fine.

### 0b. Export compliance (`ITSAppUsesNonExemptEncryption`) — LEGAL ATTESTATION
pockterm implements SSH (general-purpose encryption of arbitrary traffic via swift-crypto /
BoringSSL). This is a U.S. export-law declaration; **you must choose**, I won't guess it:

- **Declare `YES`** (encryption is non-exempt): the strict/defensible reading for a general
  SSH client. You then either (a) qualify for the mass-market exemption **5D992.c** and file
  an annual self-classification report with BIS, or (b) upload a CCATS/compliance doc. Apple
  prompts you for the encryption documentation at submission.
- **Declare `NO`** (only exempt encryption): common indie shortcut; avoids the per-build
  compliance prompt. Only correct if your use qualifies for an exemption. Riskier for an app
  whose *purpose* is encrypting connections.

Once decided, add to the **app target** Release+Debug build settings:
```
INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = YES   # or NO
```
(Works because `GENERATE_INFOPLIST_FILE = YES` injects `INFOPLIST_KEY_*` into the plist.)

### 0c. App name & bundle ID
`John-Hancock.pockterm` is not reverse-DNS but is a valid unique ID — keep it if it's already
registered, otherwise consider `com.johnhancock.pockterm`. The **App Store display name**
("pockterm") must be unique across the store; check availability in App Store Connect.

---

## 1. Repo readiness (code changes)

- [ ] **Export-compliance key** — add `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption` (see 0b).
- [ ] **App icon** — a complete 1024×1024 marketing icon must be in `Assets.xcassets/AppIcon`.
      Verify no missing slots (App Store rejects incomplete icon sets).
- [ ] **Launch screen** — currently `INFOPLIST_KEY_UILaunchScreen_Generation = YES` (generated
      blank launch screen). Acceptable; a branded one is nicer.
- [ ] **Version/build** — `MARKETING_VERSION` 1.0 / build 1 is fine for the first submission.
      Each *new* upload for the same version needs a higher build number.
- [ ] **Privacy manifest** (`PrivacyInfo.xcprivacy`) — add one to the app target if you access
      any "required-reason" APIs (e.g. `UserDefaults`, file timestamps, disk space, keyboard).
      pockterm uses UserDefaults/Keychain-style storage, so this is likely required.
- [ ] **No debug/test scaffolding shipping** — confirm the verify harness / any test-only SSH
      keys are not compiled into the Release app.
- [ ] **Third-party licenses** — Citadel, SwiftTerm, swift-crypto, swift-nio, BigInt are
      permissively licensed; keep their notices. Not a blocker, good practice.

## 2. App Review Guideline compliance (pockterm-specific)

- **2.1 App Completeness** — App Review will actually try to connect. Provide working demo
  credentials or a demo host in **App Review notes**, or reviewers can't exercise the core flow.
  SSH clients get rejected when the reviewer can't reach a server.
- **2.5.x Software Requirements** — pockterm runs code the user types on *their own* remote
  servers; it does not download/execute code to alter the app itself, so it's within bounds.
  Be ready to explain this — terminal apps sometimes get flagged under 2.5.2.
- **4.0 / Human Interface** — must feel like a finished iOS app (you've done the Liquid Glass work).
- **5.1.1 Data Collection & Privacy** — you must complete the **App Privacy** questionnaire in
  App Store Connect. Declare what the AI assistant sends off-device and to whom.
- **5.1.1(v) Account deletion** — only if you add accounts/sign-in. pockterm is local-only, so
  likely N/A. Confirm no server accounts.
- **Privacy Policy URL** — **required** because the AI assistant transmits user content to a
  model provider. You need a hosted privacy policy URL before submission.
- **AI content (1.2 / UGC-like)** — if the assistant can produce arbitrary text, be ready to
  describe safeguards. Since output isn't shared socially, this is usually light-touch, but
  disclose the model provider and that prompts leave the device.
- **Support URL** — required (a simple GitHub page or website is fine).

## 3. App Store Connect setup (your account actions)

1. Enroll in / confirm the **Apple Developer Program** (paid). Free teams can't submit.
2. Certificates, Identifiers & Profiles → register the App ID for `John-Hancock.pockterm`.
3. App Store Connect → **My Apps → +** → create the app record (name, language, bundle ID, SKU).
4. Fill in **App Information**, **Pricing**, **App Privacy**, **Age Rating**.
5. Prepare **metadata**: subtitle, description, keywords, promotional text, support URL,
   marketing URL (optional), privacy policy URL.
6. Prepare **screenshots** — required sizes: 6.9" iPhone and (since device family is 1,2)
   13" iPad. Capture on-device or simulator at the exact required pixel dimensions.

## 4. Build, upload, test, submit

1. In Xcode: set the run destination to **Any iOS Device (arm64)**, scheme = Release.
2. **Product → Archive** (needs distribution signing; automatic signing with your team handles it).
3. Organizer → **Distribute App → App Store Connect → Upload**.
4. Answer export-compliance prompt consistent with your 0b choice (or it's skipped if the
   Info.plist key is present).
5. Wait for processing → the build appears under **TestFlight**. Do a real TestFlight install
   and connect to a live server to smoke-test.
6. Attach the build to the App Store version, add **App Review notes + demo host/credentials**,
   then **Submit for Review**.

## 5. Common rejection risks for this app
- Reviewer can't connect (no demo server) → provide one in review notes. (Biggest one.)
- Missing privacy policy URL while transmitting prompts to an AI provider.
- Incomplete App Privacy questionnaire vs. actual network behavior.
- Export-compliance answer inconsistent with the app clearly doing SSH crypto.
- iOS 26.5 target flagged as unusually restrictive (not a rejection, but worth a note).
