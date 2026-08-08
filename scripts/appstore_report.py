#!/usr/bin/env python3
"""Pockterm App Store report: downloads plus any new customer reviews.

Credentials and account identifiers live outside the repo, in
~/Documents/Apps/pockterm/ (report-config.json + the AuthKey .p8).

Speed comes from three things, in order of impact:
  1. Finalised daily reports never change, so they are cached on disk forever.
     A re-run only fetches days it has never seen plus the trailing few that
     may still be settling — typically 2-3 requests instead of ~40.
  2. Whatever is left is fetched in parallel over one pooled HTTPS session.
  3. One JWT is signed per run rather than per request.

Usage:
    scripts/appstore-report                 # since first sales date
    scripts/appstore-report --days 14       # trailing window
    scripts/appstore-report --reviews-only
    scripts/appstore-report --all-reviews   # ignore the seen-review marker
"""
import argparse
import datetime
import gzip
import io
import json
import sys
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import jwt
import requests
from requests.adapters import HTTPAdapter

CONFIG_DIR = Path.home() / "Documents/Apps/pockterm"
CACHE_DIR = Path.home() / ".cache/pockterm-asc"
SALES_CACHE = CACHE_DIR / "sales"
SEEN_REVIEWS = CACHE_DIR / "seen-reviews.json"
BASE = "https://api.appstoreconnect.apple.com"

# Days this recent are re-fetched every run: Apple can still be filling them in,
# so caching them would freeze in a partial count.
VOLATILE_DAYS = 3

# https://developer.apple.com/help/app-store-connect/reference/product-type-identifiers/
PRODUCT_TYPES = {"1": "first-time downloads", "3": "re-downloads", "7": "updates"}


def load_config():
    path = CONFIG_DIR / "report-config.json"
    if not path.exists():
        sys.exit(f"missing {path} — see scripts/appstore_report.py docstring")
    return json.loads(path.read_text())


def make_session(cfg):
    key = (CONFIG_DIR / f"AuthKey_{cfg['keyId']}.p8").read_text()
    now = int(time.time())
    token = jwt.encode(
        {"iss": cfg["issuerId"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": cfg["keyId"], "typ": "JWT"},
    )
    session = requests.Session()
    session.headers["Authorization"] = f"Bearer {token}"
    adapter = HTTPAdapter(pool_connections=16, pool_maxsize=16, max_retries=2)
    session.mount("https://", adapter)
    return session


# ---------------------------------------------------------------- sales

def fetch_day(session, cfg, date):
    """One day's TSV, '' when Apple reports no data. Cached once finalised."""
    cached = SALES_CACHE / f"{date}.tsv"
    volatile = (datetime.date.today() - datetime.date.fromisoformat(date)).days < VOLATILE_DAYS
    if cached.exists() and not volatile:
        return cached.read_text()

    r = session.get(
        BASE + "/v1/salesReports",
        headers={"Accept": "application/a-gzip"},
        params={
            "filter[frequency]": "DAILY",
            "filter[reportType]": "SALES",
            "filter[reportSubType]": "SUMMARY",
            "filter[vendorNumber]": cfg["vendorNumber"],
            "filter[reportDate]": date,
        },
        timeout=60,
    )
    if r.status_code == 404:
        tsv = ""
    elif r.ok:
        tsv = gzip.decompress(r.content).decode("utf-8")
    else:
        print(f"  warn {date}: HTTP {r.status_code}", file=sys.stderr)
        return ""

    if not volatile:
        SALES_CACHE.mkdir(parents=True, exist_ok=True)
        cached.write_text(tsv)
    return tsv


def rows(tsv):
    if not tsv.strip():
        return
    reader = io.StringIO(tsv)
    header = reader.readline().rstrip("\n").split("\t")
    for line in reader:
        if line.strip():
            yield dict(zip(header, line.rstrip("\n").split("\t")))


def collect_sales(session, cfg, start, end):
    days = []
    day = start
    while day <= end:
        days.append(day.isoformat())
        day += datetime.timedelta(days=1)

    with ThreadPoolExecutor(max_workers=16) as pool:
        tsvs = list(pool.map(lambda d: fetch_day(session, cfg, d), days))

    stats = {
        "by_type": defaultdict(int),
        "by_country": defaultdict(int),
        "by_version": defaultdict(int),
        "by_device": defaultdict(int),
        "by_day": {},
        "downloads_by_day": {},
    }
    for date, tsv in zip(days, tsvs):
        total = downloads = 0
        for row in rows(tsv):
            units = int(row.get("Units", 0) or 0)
            ptype = row.get("Product Type Identifier", "?")
            stats["by_type"][ptype] += units
            stats["by_country"][row.get("Country Code", "?")] += units
            stats["by_version"][row.get("Version", "?")] += units
            stats["by_device"][row.get("Device", "?")] += units
            total += units
            if ptype == "1":
                downloads += units
        if total:
            stats["by_day"][date] = total
            stats["downloads_by_day"][date] = downloads
    return stats


# ---------------------------------------------------------------- reviews

def fetch_reviews(session, cfg):
    out = []
    url = f"{BASE}/v1/apps/{cfg['appId']}/customerReviews"
    params = {"limit": 200, "sort": "-createdDate"}
    while url:
        r = session.get(url, params=params, timeout=60)
        if not r.ok:
            print(f"  warn reviews: HTTP {r.status_code} {r.text[:160]}", file=sys.stderr)
            break
        payload = r.json()
        out.extend(payload.get("data", []))
        url = payload.get("links", {}).get("next")
        params = None  # `next` already carries the query
    return out


def load_seen():
    if SEEN_REVIEWS.exists():
        return set(json.loads(SEEN_REVIEWS.read_text()).get("ids", []))
    return set()


def save_seen(ids):
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    SEEN_REVIEWS.write_text(json.dumps(
        {"ids": sorted(ids), "updated": datetime.datetime.now().isoformat(timespec="seconds")}))


def print_reviews(reviews, seen, mark_all_new):
    if not reviews:
        print("\nREVIEWS: none yet")
        return

    new = [r for r in reviews if mark_all_new or r["id"] not in seen]
    ratings = [r["attributes"].get("rating", 0) for r in reviews]
    average = sum(ratings) / len(ratings)
    print(f"\nREVIEWS: {len(reviews)} total, average {average:.1f}★, {len(new)} new")

    if not new:
        return
    print("\n" + "=" * 68)
    print("NEW REVIEWS — read these for anything worth acting on")
    print("=" * 68)
    for r in sorted(new, key=lambda x: x["attributes"].get("createdDate", "")):
        a = r["attributes"]
        print(f"\n[{a.get('rating')}★] {a.get('title') or '(no title)'}")
        print(f"  {a.get('reviewerNickname')} · {a.get('territory')} · "
              f"{(a.get('createdDate') or '')[:10]} · id {r['id']}")
        body = (a.get("body") or "").strip()
        for line in body.splitlines():
            print(f"  | {line}")


# ---------------------------------------------------------------- output

def print_sales(stats, start, end):
    downloads = stats["by_type"].get("1", 0)
    total = sum(stats["by_type"].values())
    print(f"DOWNLOADS {start} .. {end}")
    print(f"  first-time downloads : {downloads}")
    for code, count in sorted(stats["by_type"].items()):
        if code != "1":
            print(f"  {PRODUCT_TYPES.get(code, 'type ' + code):<21}: {count}")
    print(f"  {'total units':<21}: {total}")

    if stats["by_device"]:
        devices = ", ".join(f"{k} {v}" for k, v in
                            sorted(stats["by_device"].items(), key=lambda x: -x[1]))
        print(f"  devices              : {devices}")
    if stats["by_version"]:
        versions = ", ".join(f"{k} {v}" for k, v in sorted(stats["by_version"].items()))
        print(f"  versions             : {versions}")
    if stats["by_country"]:
        top = sorted(stats["by_country"].items(), key=lambda x: -x[1])[:12]
        print(f"  top countries        : " + ", ".join(f"{k} {v}" for k, v in top)
              + f"  ({len(stats['by_country'])} total)")

    if stats["by_day"]:
        print("\n  daily (units / of which first-time):")
        for date, units in sorted(stats["by_day"].items()):
            print(f"    {date}  {units:>4}  / {stats['downloads_by_day'].get(date, 0)}")
    else:
        print("\n  no activity in this window")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, help="trailing window instead of since launch")
    ap.add_argument("--reviews-only", action="store_true")
    ap.add_argument("--all-reviews", action="store_true",
                    help="treat every review as new (ignore the seen marker)")
    args = ap.parse_args()

    cfg = load_config()
    session = make_session(cfg)
    started = time.time()

    if not args.reviews_only:
        # Apple has no data for today yet; yesterday is the newest useful day.
        end = datetime.date.today() - datetime.timedelta(days=1)
        start = (end - datetime.timedelta(days=args.days - 1) if args.days
                 else datetime.date.fromisoformat(cfg["firstSalesDate"]))
        print_sales(collect_sales(session, cfg, start, end), start, end)

    reviews = fetch_reviews(session, cfg)
    seen = load_seen()
    print_reviews(reviews, seen, args.all_reviews)
    save_seen(seen | {r["id"] for r in reviews})

    print(f"\n({time.time() - started:.1f}s)")


if __name__ == "__main__":
    main()
