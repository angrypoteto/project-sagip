"""Collects dated news reports of fires in Manila from Asia Fire News, the
archive kept by the Center for Fire Science and Technology of Tokyo
University of Science (https://gcoe.tus-fire.com/asia_news/). Each entry
there is a reprint of one news report, with its date and a link to the
original (GMA, Inquirer, and others).

This is a stand-in for MDRRMD's and BFP's own records while those are
asked for (Joshua, 2026-10-12). What it gives is only the fires that made
the news and were picked up by the archive: a part of what happened, and
the larger fires more than the small ones.

Two steps, both kept on disk so nothing is asked for twice:
  1. the archive's search for "Manila", page by page, back to --since;
  2. each entry's own page, for the text of the report.

Usage:
  python ml/forecast/data_prep/collect_fire_news.py --since 2021-01-01

Writes ml/forecast/build/fire_news/ (git-ignored): list.json and one
text file per entry. locate_fire_news.py turns them into incidents.
"""

import argparse
import html
import json
import re
import time
import urllib.parse
import urllib.request
from datetime import date
from pathlib import Path

FORECAST = Path(__file__).resolve().parents[1]
OUT = FORECAST / "build" / "fire_news"
BASE = "https://gcoe.tus-fire.com/asia_news/"
AGENT = "project-sagip capstone research (student project; one request a second)"

# Older entries carry the country in the title; newer ones do not. The
# search word is "Manila", and locate_fire_news.py keeps only the city's.
ENTRY = re.compile(
    r'<h3><a href="https://gcoe\.tus-fire\.com/asia_news/\?p=(\d+)">(\d{8}) (?:Philippines )?(.*?)</a></h3>',
    re.S,
)


def get(url):
    request = urllib.request.Request(url, headers={"User-Agent": AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        body = response.read().decode("utf-8", errors="replace")
    time.sleep(1)
    return body


def collect_list(since):
    entries, page = {}, 1
    while True:
        query = urllib.parse.urlencode({"s": "Manila", "paged": page})
        found = ENTRY.findall(get(f"{BASE}?{query}"))
        if not found:
            break
        for entry_id, stamp, title in found:
            day = date(int(stamp[:4]), int(stamp[4:6]), int(stamp[6:]))
            if day >= since:
                entries[entry_id] = {
                    "id": entry_id,
                    "date": day.isoformat(),
                    "title": html.unescape(title).strip(),
                }
        oldest = min(stamp for _, stamp, _ in found)
        print(f"page {page}: {len(found)} entries, oldest {oldest}, kept {len(entries)}")
        # No stop at the first old entry: the search lists the entries with
        # "Manila" in the title first and then, from the newest again, those
        # that only mention it in the text ("Fire hits Tondo residential area").
        page += 1
    return sorted(entries.values(), key=lambda e: e["date"])


def article_text(page):
    """The report's text and the link to the original."""
    start = page.find('<section class="column_right">')
    body = page[start:] if start >= 0 else page
    end = body.find("</section>")
    body = body[:end] if end >= 0 else body
    links = re.findall(r'href="(https?://[^"]+)"', body)
    source = next((u for u in links if "tus-fire.com" not in u), "")
    text = re.sub(r"<(script|style).*?</\1>", " ", body, flags=re.S)
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"\s+", " ", html.unescape(text)).strip()
    return text, source


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--since", default="2021-01-01", type=date.fromisoformat)
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)

    listing = OUT / "list.json"
    if listing.exists():
        entries = json.loads(listing.read_text(encoding="utf-8"))
    else:
        entries = collect_list(args.since)
        listing.write_text(json.dumps(entries, indent=1), encoding="utf-8")
    print(f"{len(entries)} entries since {args.since}")

    for n, entry in enumerate(entries, 1):
        target = OUT / f"{entry['id']}.json"
        if target.exists():
            continue
        text, source = article_text(get(f"{BASE}?p={entry['id']}"))
        target.write_text(
            json.dumps({**entry, "source_url": source, "text": text}, indent=1),
            encoding="utf-8",
        )
        if n % 25 == 0:
            print(f"{n} of {len(entries)}")
    print("done")


if __name__ == "__main__":
    main()
