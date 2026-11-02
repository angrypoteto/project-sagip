"""Fires in the City of Manila from TXTFIRE Philippines' public Telegram
channel (https://t.me/txtfirephilippines), for the years its website does
not cover (Joshua, 2026-11-02: "can you get fire data from the txt fire?
... they have a telegram account that notify its subscriber").

The website (collect_txtfire.py) stops in mid-2022 and has almost nothing in
2020; the channel posts every alert from October 2018 to today. This reads
the channel's public web preview (https://t.me/s/txtfirephilippines, 20
posts a page, no account needed), one page at a time with a pause between
requests, and keeps each page under data/downloads/txtfire_telegram/ so a
rerun reads the saved pages instead of asking again.

Each alert is a post such as "As of 2:52:13 PM / Fire Alert! / ->Brgy 462
P. Campa Sampaloc Manila : 1st Alarm", posted twice (two footers), then
again for each new status. The rules are collect_txtfire.py's: alerts placed
in the City of Manila, the updates for one place on one day grouped into one
fire, and the same kinds (alarm, fire with no alarm raised, false alarm,
unverified). Post times are UTC; dates here are Manila's (UTC+8).

Usage (from the repo root):
  .venv/Scripts/python ml/forecast/data_prep/collect_txtfire_telegram.py [--since 2021-01-01]

Writes ml/forecast/data/manila_fire_txtfire_telegram.csv (same columns as
manila_fire_txtfire.csv). Credit: TXTFIRE Philippines.
"""

import argparse
import csv
import html
import re
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from collect_txtfire import ALARM, USER_AGENT, barangay_of, district_of, in_manila, normal_place  # noqa: E402

FORECAST = Path(__file__).resolve().parents[1]
CACHE = FORECAST / "data" / "downloads" / "txtfire_telegram"
OUT = FORECAST / "data" / "manila_fire_txtfire_telegram.csv"
CHANNEL = "txtfirephilippines"
PAUSE = 1.5  # seconds between requests
MANILA = timezone(timedelta(hours=8))

TEXT = re.compile(r'<div class="tgme_widget_message_text[^>]*>(.*?)</div>', re.S)
TIME = re.compile(r'<time datetime="([^"]+)"')
LINE = re.compile(r"^-+>\s*(?P<place>.+?)\s*:\s*(?P<status>[^:]+?)\s*$")


def page(before):
    """The channel page with the 20 posts before [before] (None: newest)."""
    name = CACHE / f"before_{before or 'newest'}.html"
    if before and name.exists():
        return name.read_text(encoding="utf-8")
    url = f"https://t.me/s/{CHANNEL}" + (f"?before={before}" if before else "")
    for attempt in range(5):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=60) as r:
                text = r.read().decode("utf-8", "replace")
            break
        except urllib.error.HTTPError as e:
            if e.code != 429 or attempt == 4:
                raise
            time.sleep(30 * (attempt + 1))
        except OSError:
            if attempt == 4:
                raise
            time.sleep(10 * (attempt + 1))
    time.sleep(PAUSE)
    if before:
        CACHE.mkdir(parents=True, exist_ok=True)
        name.write_text(text, encoding="utf-8")
    return text


def posts_of(text):
    """The page's posts, each read only from its own part of the page (a
    photo post has no text and must not borrow the next post's)."""
    out = []
    marker = f'data-post="{CHANNEL}/'
    chunks = text.split(marker)[1:]
    for chunk in chunks:
        post_id = re.match(r"(\d+)", chunk)
        at = TIME.search(chunk)
        if not post_id or not at:
            continue
        raw = TEXT.search(chunk)
        body = html.unescape(re.sub(r"<[^>]+>", "", re.sub(r"<br\s*/?>", "\n", raw.group(1) if raw else "")))
        out.append({
            "id": int(post_id.group(1)),
            "at": datetime.fromisoformat(at.group(1)).astimezone(MANILA),
            "text": body,
        })
    return out


def collect(since):
    """Every post from [since] (a Manila date) to the newest, oldest first."""
    posts = {p["id"]: p for p in posts_of(page(None))}
    before = min(posts)
    pages = 1
    while True:
        batch = posts_of(page(before))
        pages += 1
        if not batch:
            break
        for p in batch:
            posts[p["id"]] = p
        before = min(p["id"] for p in batch)
        oldest = min(p["at"] for p in batch).date()
        if pages % 50 == 0:
            print(f"  {pages} pages, back to {oldest} (post {before})", flush=True)
        if oldest < since or before <= 1:
            break
    return sorted((p for p in posts.values() if p["at"].date() >= since), key=lambda p: p["id"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--since", default="2021-01-01")
    args = parser.parse_args()
    since = datetime.strptime(args.since, "%Y-%m-%d").date()

    posts = collect(since)
    alerts, other = [], 0
    for p in posts:
        if "fire alert" not in p["text"].lower():
            other += 1
            continue
        for line in p["text"].splitlines():
            m = LINE.match(line.strip())
            if m and in_manila(m.group("place")):
                alerts.append({
                    "time": p["at"].strftime("%Y-%m-%dT%H:%M"),
                    "place": m.group("place").strip(),
                    "status": m.group("status").strip(),
                    "link": f"https://t.me/{CHANNEL}/{p['id']}",
                })

    fires = {}
    for a in alerts:
        key = (a["time"][:10], normal_place(a["place"]))
        f = fires.setdefault(key, {"first": a["time"], "place": a["place"], "statuses": [], "link": a["link"]})
        if a["status"] not in f["statuses"]:  # each alert is posted twice
            f["statuses"].append(a["status"])
    rows = []
    for (day, _), f in sorted(fires.items()):
        statuses = " | ".join(f["statuses"])
        alarm = ALARM.search(statuses)
        low = statuses.lower()
        if alarm:
            kind = "alarm"
        elif "false" in low or "negative" in low:
            kind = "false alarm"
        elif re.search(r"under control|fire out|fire ?out|extinguished", low):
            kind = "fire, no alarm raised"
        else:
            kind = "unverified"
        rows.append({
            "incident_id": f"TXTFIRE-TG-{f['first'].replace(':', '').replace('-', '')}",
            "date": day,
            "time": f["first"][11:16],
            "hazard": "fire",
            "place": f["place"],
            "barangay": barangay_of(f["place"]),
            "district": district_of(f["place"]),
            "highest_alarm": alarm.group(0) if alarm else "",
            "kind": kind,
            "statuses": statuses[:300],
            "source_url": f["link"],
        })
    with OUT.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(f"{len(posts)} posts since {since}, {other} not fire alerts, {len(alerts)} alert lines in Manila, "
          f"{len(rows)} fires")
    by_kind, by_year = {}, {}
    for r in rows:
        by_kind[r["kind"]] = by_kind.get(r["kind"], 0) + 1
        by_year[r["date"][:4]] = by_year.get(r["date"][:4], 0) + 1
    print(by_kind)
    print(dict(sorted(by_year.items())))


if __name__ == "__main__":
    main()
