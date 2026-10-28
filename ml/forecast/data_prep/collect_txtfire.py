"""Fires in the City of Manila from TXTFIRE Philippines' public fire alerts
(https://txtfire.net, a volunteer fire and rescue network in Metro Manila),
as a stand-in for MDRRMD's and BFP's records (Objective 2).

Each alert is a short post: "Fire Alert! ->Brgy 462 P. Campa Sampaloc
Manila : 1st Alarm", then updates for the same place ("Fire Under Control",
"Fire Out"). This reads every post that mentions Manila through the site's
public WordPress API (robots.txt allows it), keeps the alerts placed in the
City of Manila, and groups the updates for one place on one day into one
fire. A place whose alerts never got past "For Verification", or were
called a false alarm, is kept but marked, so the preparation can count and
drop it.

Most alerts are from 2018, 2019, 2021, and the first half of 2022; the site
posted almost none in 2020 and none after mid-2022.

Usage (from the repo root):
  .venv/Scripts/python ml/forecast/data_prep/collect_txtfire.py

Writes ml/forecast/data/manila_fire_txtfire.csv. Credit: TXTFIRE Philippines.
"""

import csv
import html
import json
import re
import time
import urllib.request
from pathlib import Path

FORECAST = Path(__file__).resolve().parents[1]
OUT = FORECAST / "data" / "manila_fire_txtfire.csv"
API = "https://txtfire.net/wp-json/wp/v2/posts"
USER_AGENT = "project-sagip (capstone; Manila MDRRMD)"
DISTRICTS = {
    "tondo": "Tondo", "binondo": "Binondo", "quiapo": "Quiapo", "san nicolas": "San Nicolas",
    "sta cruz": "Santa Cruz", "santa cruz": "Santa Cruz", "sampaloc": "Sampaloc", "san miguel": "San Miguel",
    "ermita": "Ermita", "intramuros": "Intramuros", "malate": "Malate", "paco": "Paco", "pandacan": "Pandacan",
    "port area": "Port Area", "sta ana": "Santa Ana", "santa ana": "Santa Ana", "san andres": "San Andres",
    "sta mesa": "Santa Mesa", "santa mesa": "Santa Mesa", "baseco": "Tondo",
}
# 2021-2022: "Fire Alert! ->PLACE : STATUS"; 2018-2019: "#FireAlert! ->PLACE : STATUS #NCR".
ALERT = re.compile(r"#?Fire\s?Alert!\s*-+>\s*(?P<place>.+?)\s*:\s*(?P<status>[^:#]+?)\s*(?:#\w+\s*)*$", re.I)
ALARM = re.compile(r"(\d+)(?:st|nd|rd|th)\s+alarm|task\s*force\s*(alpha|bravo|charlie|delta|echo)|general alarm", re.I)
OTHER_CITY = re.compile(r"quezon city|\bqc\b|caloocan|malabon|navotas|valenzuela|pasay|makati|mandaluyong|"
                        r"san juan|pasig|marikina|taguig|para[nñ]aque|las pi[nñ]as|muntinlupa|pateros|"
                        r"cavite|bulacan|rizal|laguna", re.I)


def fetch_all():
    posts, page = [], 1
    while True:
        url = f"{API}?search=manila&per_page=100&page={page}&_fields=date,content,link"
        for attempt in range(4):
            try:
                req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
                with urllib.request.urlopen(req, timeout=90) as r:
                    batch = json.load(r)
                    total_pages = int(r.headers.get("X-WP-TotalPages", "1"))
                break
            except Exception:  # noqa: BLE001
                if attempt == 3:
                    raise
                time.sleep(3 * (attempt + 1))
        posts += batch
        print(f"page {page}/{total_pages}", flush=True)
        if page >= total_pages:
            return posts
        page += 1
        time.sleep(0.5)


def text_of(post):
    return html.unescape(" ".join(re.sub(r"<[^>]+>", " ", post["content"]["rendered"]).split()))


def in_manila(place):
    low = place.lower().replace(".", "")
    if OTHER_CITY.search(low) or "metro manila" in low:
        return False
    return "manila" in low or any(d in low for d in DISTRICTS)


def normal_place(place):
    low = re.sub(r"[^a-z0-9 ]", " ", place.lower().replace("ñ", "n"))
    low = re.sub(r"\b(city of manila|manila city|manila|brgy|barangay|st|street|cor|corner|ave|avenue)\b", " ", low)
    return " ".join(low.split())


def barangay_of(place):
    m = re.search(r"\b(?:brgy|barangay|bgy)\.?\s*(\d{1,3}(?:-?[a-c])?)\b", place, re.I)
    return m.group(1).upper() if m else ""


def district_of(place):
    low = place.lower().replace(".", "")
    for key, name in DISTRICTS.items():
        if key in low:
            return name
    return ""


def main():
    posts = fetch_all()
    alerts, other = [], 0
    for p in posts:
        m = ALERT.search(text_of(p))
        if not m:
            other += 1
            continue
        if not in_manila(m.group("place")):
            continue
        alerts.append({"time": p["date"], "place": m.group("place").strip(), "status": m.group("status").strip(),
                       "link": p["link"]})
    alerts.sort(key=lambda a: a["time"])

    fires = {}
    for a in alerts:
        key = (a["time"][:10], normal_place(a["place"]))
        f = fires.setdefault(key, {"first": a["time"], "place": a["place"], "statuses": [], "link": a["link"]})
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
            "incident_id": f"TXTFIRE-{f['first'][:16].replace(':', '').replace('-', '')}",
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
    print(f"{len(posts)} posts read, {other} not fire alerts, {len(alerts)} alerts in Manila, {len(rows)} fires")
    by_kind = {}
    for r in rows:
        by_kind[r["kind"]] = by_kind.get(r["kind"], 0) + 1
    print(by_kind)


if __name__ == "__main__":
    main()
