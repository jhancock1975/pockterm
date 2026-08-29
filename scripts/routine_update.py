#!/usr/bin/env python3
"""Pockterm routine update check: dependencies, advisories, and secret hygiene.

Read-only by default — it reports, it does not change the repo. Pass --resolve
to actually re-pin dependencies.

    scripts/routine-update              # report only
    scripts/routine-update --resolve    # also update Package.resolved

Sections:
  1. Dependency versions   pinned vs. latest upstream release
  2. Supply chain          every package must come from a vetted source
  3. Security advisories   GitHub advisories, matched against the pinned version
  4. Secret scan           tracked files + git history
  5. Packaging identity    personal paths / identifiers in a built binary

Exit code is 1 when anything actionable is found, so this can gate a release.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RESOLVED = REPO / "pockterm.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

# Pinned identity -> GitHub repo to check for releases.
UPSTREAM = {
    "bigint": "attaswift/BigInt",
    "citadel": "orlandos-nl/Citadel",
    "swift-argument-parser": "apple/swift-argument-parser",
    "swift-asn1": "apple/swift-asn1",
    "swift-atomics": "apple/swift-atomics",
    "swift-collections": "apple/swift-collections",
    "swift-crypto": "apple/swift-crypto",
    "swift-log": "apple/swift-log",
    "swift-nio": "apple/swift-nio",
    "swift-system": "apple/swift-system",
    "swiftterm": "migueldeicaza/SwiftTerm",
    # Citadel needs a patched NIOSSH. We declare the Citadel author's own fork at
    # the root so the source is explicit rather than inherited; see CAPPED.
    "swift-nio-ssh": "Joannis/swift-nio-ssh",
}

# Advisory package names to the identity they map to in Package.resolved.
ADVISORY_PACKAGES = {
    "github.com/apple/swift-nio": "swift-nio",
    "swift-nio": "swift-nio",
    "swift-crypto": "swift-crypto",
    "github.com/apple/swift-crypto": "swift-crypto",
    "Citadel": "citadel",
    "SwiftTerm": "swiftterm",
}

# Updates we deliberately cannot or should not take, so the check reports them
# as context instead of nagging every run.
CAPPED = {
    "swift-crypto": "Citadel pins <4.0.0, and 4.0.0-4.3.0 carry GHSA-9m44-rr2w-ppp7",
    # Citadel 0.12.1 declares Wellz26/swift-nio-ssh, a 0-star third-party fork
    # carrying a 0.3.6 tag that upstream does not have — and Citadel's range
    # makes that tag the highest match. We hold Citadel at 0.12.0, the last
    # release that declares the author's own fork directly, so the third-party
    # fork is never even fetched.
    #
    # DO NOT BUMP CITADEL TO 0.12.1+ WITHOUT RE-READING docs/backlog.md.
    # Taking that bump silently puts a zero-star account back in the graph.
    # Verified 2026-08-29 that 0.12.0 costs us nothing: 0.12.1's only client
    # change is additive (withExec, +57/-0, which we do not use) and its stderr
    # fix is server-side, while SSHEngine.exec merges streams remotely itself.
    # BigInt is transitive via Citadel and never imported by the app. Citadel
    # declares `from: "5.2.0"`, which caps it below 6.0.0, and Citadel main
    # still does. Taking 6.x would mean declaring BigInt at our root to force
    # Citadel to compile against a major it doesn't claim to support — in its
    # RSA path — and 6.0.0/6.0.1 contain only a WASI fix, CI runners, and a
    # migration of BigInt's own tests to Swift Testing. Nothing for an iOS app.
    # Revisit only if Citadel widens its range or an advisory lands on 5.x.
    "bigint": "held <6.0.0 by Citadel; 6.x is a WASI fix and test migration, no iOS benefit",
    "citadel": "held at 0.12.0; 0.12.1 declares a third-party swift-nio-ssh fork",
    "swift-nio-ssh": "held <0.4.0 by Citadel; declared at the root, not inherited",
}

# ---------------------------------------------------------------- trust policy
#
# Supply-chain rule: every dependency must come from a source we have actually
# vetted. Anything not listed here is treated as untrusted and reported, even if
# it builds fine — that is the npm event-stream failure mode, where a legitimate
# package quietly changes hands or gains an obscure transitive dependency.
#
# To add an entry you must have looked at the repo: who owns it, how long it has
# existed, who commits to it, and what a fork changes versus its parent.

TRUSTED_OWNERS = {
    "apple": "Apple official",
    "swiftlang": "Apple/Swift official",
}

TRUSTED_REPOS = {
    "migueldeicaza/SwiftTerm":
        "Miguel de Icaza; 1.6k stars, active since 2019. The terminal emulator.",
    "attaswift/BigInt":
        "Karoly Lorentey; 815 stars, active since 2015. Widely used, pulled in by Citadel.",
    "orlandos-nl/Citadel":
        "Joannis Orlandos (Vapor core team); 380 stars, active since 2020. The SSH layer.",
    "Joannis/swift-nio-ssh":
        "Citadel author's fork of apple/swift-nio-ssh. History is Apple's (113 commits by "
        "Cory Benfield); the delta is public-API and platform work Citadel needs. Audited "
        "2026-08-08 — legitimate but 4 years behind Apple; see docs/dependency-policy.md.",
}

findings = []


def note(section, msg):
    findings.append(f"[{section}] {msg}")


def sh(*args, **kw):
    return subprocess.run(args, capture_output=True, text=True, cwd=REPO, **kw).stdout.strip()


def gh_json(path):
    out = sh("gh", "api", path)
    try:
        return json.loads(out) if out else None
    except json.JSONDecodeError:
        return None


def parse_version(v):
    """'1.13.0' / 'v1.13.0' -> (1, 13, 0); unparseable sorts lowest."""
    m = re.search(r"(\d+)\.(\d+)\.(\d+)", v or "")
    return tuple(int(g) for g in m.groups()) if m else (-1, -1, -1)


def in_range(version, spec):
    """Is `version` inside a GitHub advisory range like '>= 4.0.0, <= 4.3.0'?"""
    v = parse_version(version)
    for clause in (spec or "").split(","):
        clause = clause.strip()
        m = re.match(r"(>=|<=|>|<|=)\s*(.+)", clause)
        if not m:
            continue
        op, bound = m.group(1), parse_version(m.group(2))
        if op == ">=" and not v >= bound: return False
        if op == "<=" and not v <= bound: return False
        if op == ">" and not v > bound: return False
        if op == "<" and not v < bound: return False
        if op == "=" and not v == bound: return False
    return True


# ------------------------------------------------------------------ sections

def pins():
    data = json.loads(RESOLVED.read_text())
    return {p["identity"]: p["state"].get("version") for p in data["pins"]}


def check_dependencies(current):
    print("1. DEPENDENCY VERSIONS")
    stale = 0
    for identity, version in sorted(current.items()):
        repo = UPSTREAM.get(identity)
        if not repo:
            # Anything not on the known list is a fork or unusual source.
            print(f"   ?  {identity:<24} {version:<10} (no upstream mapping — review manually)")
            note("deps", f"{identity} has no known upstream; verify its source is trusted")
            continue
        latest = (gh_json(f"repos/{repo}/releases/latest") or {}).get("tag_name", "")
        if latest and parse_version(latest) > parse_version(version):
            if identity in CAPPED:
                print(f"   -- {identity:<24} {version:<10} ({latest} exists; {CAPPED[identity]})")
                continue
            print(f"   ^  {identity:<24} {version:<10} -> {latest}")
            stale += 1
        else:
            print(f"   ok {identity:<24} {version}")
    if stale:
        note("deps", f"{stale} dependency update(s) available — run with --resolve")
    print()


def check_supply_chain():
    """Every resolved package must come from a vetted source.

    Deliberately allowlist-based rather than heuristic: a package that looks
    healthy today (stars, activity) is exactly what a hijacked package looks
    like. The only durable question is whether a human has vetted this source.
    """
    print("2. SUPPLY CHAIN — dependency provenance")
    data = json.loads(RESOLVED.read_text())
    untrusted = 0
    for pin in sorted(data["pins"], key=lambda p: p["identity"]):
        repo = re.sub(r"^https://github\.com/|\.git$", "", pin["location"])
        owner = repo.split("/")[0]
        if owner in TRUSTED_OWNERS:
            print(f"   ok {repo:<34} {TRUSTED_OWNERS[owner]}")
        elif repo in TRUSTED_REPOS:
            print(f"   ok {repo:<34} vetted")
        else:
            untrusted += 1
            print(f"   !! {repo:<34} NOT VETTED")
            meta = gh_json(f"repos/{repo}") or {}
            parent = (meta.get("parent") or {}).get("full_name")
            print(f"      stars={meta.get('stargazers_count', '?')} "
                  f"created={(meta.get('created_at') or '?')[:10]} "
                  f"pushed={(meta.get('pushed_at') or '?')[:10]}"
                  + (f" fork_of={parent}" if parent else ""))
            print("      Review it, then add to TRUSTED_REPOS with a reason — or remove it.")
            note("supply-chain", f"{repo} is not on the vetted list")
    if not untrusted:
        print(f"   ok all {len(data['pins'])} packages come from vetted sources")
    print()


def check_advisories(current):
    print("3. SECURITY ADVISORIES")
    advisories = gh_json("/advisories?ecosystem=swift&per_page=100") or []
    hits = 0
    for adv in advisories:
        for vuln in adv.get("vulnerabilities") or []:
            name = (vuln.get("package") or {}).get("name")
            identity = ADVISORY_PACKAGES.get(name)
            if not identity or identity not in current:
                continue
            version = current[identity]
            if in_range(version, vuln.get("vulnerable_version_range")):
                hits += 1
                print(f"   !! {adv['ghsa_id']} [{adv['severity']}] {identity} {version}")
                print(f"      {adv['summary']}")
                print(f"      fixed in: {vuln.get('first_patched_version')}")
                note("vuln", f"{adv['ghsa_id']} affects {identity} {version}")
    if not hits:
        print(f"   ok no advisory affects the {len(current)} pinned versions "
              f"({len(advisories)} checked)")
    print()


def check_secrets():
    print("4. SECRET SCAN")
    patterns = {
        "private key block": r"BEGIN (RSA|OPENSSH|EC|DSA|PRIVATE)",
        # AWS: the infra scripts run against a live account, so a leaked key here
        # is worse than any app secret. Long-lived ids, STS ids, and the secret
        # itself, which has no distinctive prefix and must be caught by context.
        "AWS access key id": r"(AKIA|ASIA)[0-9A-Z]{16}",
        "AWS secret key": r"(?i)aws_?secret_?access_?key\s*[:=]\s*[\"']?[A-Za-z0-9/+=]{40}",
        "AWS session token": r"(?i)aws_?session_?token\s*[:=]\s*[\"']?[A-Za-z0-9/+=]{50,}",
        "assigned secret": r"(password|passwd|api[_-]?key|secret|token)[a-zA-Z_]* *[:=] *[\"'][^\"'{}$<]{8,}[\"']",
        "bearer token": r"(ghp_|github_pat_|sk-[A-Za-z0-9]{20,})",
    }
    tracked = sh("git", "ls-files").splitlines()
    clean = True
    # This file necessarily contains secret-shaped strings — they are the
    # patterns. Scanning it would flag itself every run, and a check that always
    # cries wolf is a check nobody reads. The high-confidence AWS rules below
    # cannot self-match, so they still cover it.
    scannable = [f for f in tracked if f != "scripts/routine_update.py"]
    for label, pattern in patterns.items():
        out = subprocess.run(["git", "grep", "-nIE", pattern, "--"] + scannable,
                             capture_output=True, text=True, cwd=REPO).stdout.strip()
        # Placeholders are the documented way to keep real values out.
        real = [ln for ln in out.splitlines()
                if not re.search(r"<[A-Z_]+>|example|placeholder|REDACTED|xxxx", ln, re.I)]
        if real:
            clean = False
            print(f"   !! {label}:")
            for ln in real[:5]:
                print(f"      {ln[:150]}")
            note("secret", f"{label} found in tracked files")
    # ...but still check the scanner itself for real AWS keys, which cannot
    # match their own pattern definitions.
    scanner = (REPO / "scripts/routine_update.py").read_text()
    if re.search(r"(AKIA|ASIA)[0-9A-Z]{16}", scanner):
        clean = False
        print("   !! scripts/routine_update.py contains a real AWS access key id")
        note("secret", "AWS key in routine_update.py")

    # The infra scripts run against a live AWS account. They must authenticate
    # from the ambient CLI config and never carry credentials of their own, so
    # they get checked explicitly rather than relying on the generic patterns.
    for script in ("scripts/provision-demo-host.sh", "scripts/teardown-demo-host.sh"):
        path = REPO / script
        if not path.exists():
            continue
        body = path.read_text()
        bad = []
        if re.search(r"(AKIA|ASIA)[0-9A-Z]{16}", body):
            bad.append("access key id")
        if re.search(r"(?i)aws_?secret_?access_?key\s*[:=]", body):
            bad.append("secret access key")
        if re.search(r"(?i)aws_?session_?token\s*[:=]", body):
            bad.append("session token")
        # --profile is not a secret, but it pins the script to one operator's
        # machine and is usually a sign credentials are being wired in by hand.
        if re.search(r"--profile\s+\S", body):
            bad.append("hardcoded --profile")
        if bad:
            clean = False
            print(f"   !! {script} carries AWS credentials: {', '.join(bad)}")
            note("secret", f"{script} carries AWS credentials ({', '.join(bad)})")
        else:
            print(f"   ok {script} authenticates from ambient AWS config, carries no credentials")

    # Files that should never be tracked at all, regardless of content.
    banned = [f for f in tracked
              if re.search(r"\.(p8|pem|key|p12|pfx|cer|mobileprovision)$|(^|/)(authorized_keys|id_rsa|id_ed25519)$", f)]
    if banned:
        clean = False
        print(f"   !! sensitive file types tracked: {banned}")
        note("secret", f"sensitive files tracked: {banned}")
    if clean:
        print(f"   ok no secrets in {len(tracked)} tracked files")
    print()


def check_packaging():
    print("5. PACKAGING IDENTITY")
    # Every built binary, not just the newest: a clean Debug build sitting on
    # top of a leaky Release archive would otherwise read as all-clear.
    apps = sorted(REPO.glob("build/**/pockterm.app"))
    binaries = [a / "pockterm" for a in apps if (a / "pockterm").exists()]
    if not binaries:
        print("   -- no built binary found; run scripts/package-release first")
        print()
        return
    for binary in binaries:
        strings = sh("strings", "-a", str(binary))
        found = re.findall(r"/Users/[A-Za-z0-9._-]+", strings)
        rel = binary.relative_to(REPO)
        if found:
            print(f"   !! {len(found)} personal build paths in {rel}: {sorted(set(found))}")
            note("packaging", f"personal paths embedded in {rel}")
        else:
            print(f"   ok {rel}")
    if any("personal paths" in f for f in findings):
        print("      build via scripts/package-release, which archives from a neutral path")
    print()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--resolve", action="store_true",
                    help="re-pin dependencies to the newest allowed versions")
    args = ap.parse_args()

    print(f"pockterm routine update check\n{'=' * 60}\n")
    current = pins()

    check_dependencies(current)
    check_supply_chain()
    check_advisories(current)
    check_secrets()
    check_packaging()

    if args.resolve:
        print("RE-RESOLVING DEPENDENCIES")
        # A plain -resolvePackageDependencies reuses cached workspace state and
        # will report "no changes" even when updates exist. Resolving into a
        # throwaway derived-data path forces a real re-resolution.
        RESOLVED.unlink(missing_ok=True)
        subprocess.run(
            ["xcodebuild", "-project", "pockterm.xcodeproj", "-scheme", "pockterm",
             "-derivedDataPath", "/tmp/pockterm-resolve", "-skipPackagePluginValidation",
             "-resolvePackageDependencies"],
            cwd=REPO, capture_output=True, text=True)
        after = pins()
        changes = [f"   {k}: {current.get(k)} -> {after[k]}"
                   for k in after if current.get(k) != after[k]]
        print("\n".join(changes) if changes else "   (already newest allowed)")
        print("\n   now run: scripts/test.sh --build")
        print()

    print("=" * 60)
    if findings:
        print(f"{len(findings)} item(s) need attention:")
        for f in findings:
            print(f"  - {f}")
        return 1
    print("Nothing to do — dependencies current, no advisories, no secrets, clean packaging.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
