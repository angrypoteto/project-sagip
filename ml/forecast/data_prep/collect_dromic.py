"""Incidents in the City of Manila from DSWD's DROMIC reports (Disaster
Response Operations Monitoring and Information Center,
https://dromic.dswd.gov.ph), as a stand-in for MDRRMD's records
(Objective 2).

DROMIC publishes one page per disaster in which families were affected or
displaced, with its situation reports as PDFs. Two kinds are read:

  fires   every page whose title names a fire in Manila. The title gives
          the barangay(s) and the date: "Fire Incident in Brgy. 745, City of
          Manila [14 Jul 2026]". Only fires that affected families are on
          DROMIC (mostly homes), not every fire BFP answers.
  weather every page for a monsoon, tropical cyclone, low pressure area,
          shear line, or flooding event that is not named after another
          province or region. Its latest report is downloaded and searched
          for the City of Manila; when Manila is in it, the barangays listed
          under Manila are kept.

Usage (from the repo root):
  .venv/Scripts/python ml/forecast/data_prep/collect_dromic.py

Reports are PDFs, or Word files for 2018 to 2020; the 2016 and 2017 ones
were Google Docs that no longer open. Downloads go to
ml/forecast/data/downloads/dromic/ (git-ignored). Writes
ml/forecast/data/manila_fire_dromic.csv and
ml/forecast/data/manila_weather_events_dromic.csv. Credit: DSWD DROMIC.
"""

import csv
import html
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime
from pathlib import Path

FORECAST = Path(__file__).resolve().parents[1]
DATA = FORECAST / "data"
DOWNLOADS = DATA / "downloads" / "dromic"
SITE = "https://dromic.dswd.gov.ph"
USER_AGENT = "project-sagip (capstone; Manila MDRRMD)"

MONTHS = {m: i for i, m in enumerate(
    ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"], start=1)}
DISTRICTS = ("tondo", "binondo", "quiapo", "san nicolas", "santa cruz", "sta cruz", "sampaloc", "san miguel",
             "ermita", "intramuros", "malate", "paco", "pandacan", "port area", "santa ana", "sta ana",
             "san andres", "sta mesa", "santa mesa")
WEATHER = re.compile(r"monsoon|habagat|typhoon|tropical|(^|-)tc-|storm|lpa|low-pressure|shear|flood|trough|itcz|"
                     r"intertropical|heavy-rain|frontal", re.I)
ELSEWHERE = re.compile(
    r"cebu|davao|iloilo|leyte|samar|bohol|negros|mindanao|visayas|caraga|bicol|albay|sorsogon|camarines|masbate|"
    r"catanduanes|cagayan|isabela|ilocos|abra|benguet|zamboanga|cotabato|bukidnon|lanao|maguindanao|sultan|sulu|"
    r"basilan|tawi|surigao|agusan|misamis|palawan|mindoro|marinduque|romblon|aklan|antique|capiz|guimaras|aurora|"
    r"nueva|pangasinan|la-union|apayao|kalinga|ifugao|mountain-province|batanes|tarlac|zambales|bataan|pampanga|"
    r"bulacan|cavite|laguna|batangas|rizal|barmm|sarangani|biliran|general-santos|region-|mimaropa|-car-|in-car|"
    r"quezon-city|malabon|marikina|valenzuela|navotas|caloocan|pasig|taguig|paranaque|las-pinas|muntinlupa|makati|"
    r"pasay|mandaluyong|san-juan|pateros", re.I)


def get(url, binary=False, tries=4):
    for attempt in range(tries):
        try:
            safe = urllib.parse.quote(url, safe=":/%?=&#+,;~")
            req = urllib.request.Request(safe, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=90) as r:
                body = r.read()
                return body if binary else body.decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            if e.code == 404 or attempt == tries - 1:
                raise
            time.sleep(3 * (attempt + 1))
        except Exception:  # noqa: BLE001 - retried, then reported
            if attempt == tries - 1:
                raise
            time.sleep(3 * (attempt + 1))


def all_posts():
    index = get(f"{SITE}/wp-sitemap.xml")
    posts = []
    for sitemap in re.findall(r"<loc>([^<]+wp-sitemap-posts-post-\d+\.xml)</loc>", index):
        posts += re.findall(r"<loc>([^<]+)</loc>", get(sitemap))
    return posts


def page(url):
    text = get(url)
    title = html.unescape(re.search(r"<title>([^<]+)", text).group(1)).replace(" – DROMIC", "").strip()
    pdfs = sorted(set(re.findall(r'href="(https://dromic\.dswd\.gov\.ph/wp-content/uploads/[^"]+\.(?:pdf|docx))"', text)))
    return title, pdfs


def title_date(title):
    """The date in square brackets, e.g. [14 Jul 2026] or [March 10 2024]."""
    for inside in re.findall(r"\[([^\]]+)\]", title):
        cleaned = inside.replace(",", " ").replace(".", " ")
        for fmt in ("%d %b %Y", "%d %B %Y", "%B %d %Y", "%b %d %Y"):
            try:
                return datetime.strptime(" ".join(cleaned.split()), fmt).date()
            except ValueError:
                continue
        words = cleaned.lower().split()
        if len(words) == 3 and words[1][:3] in MONTHS and words[0].isdigit() and words[2].isdigit():
            return date(int(words[2]), MONTHS[words[1][:3]], int(words[0]))
    return None


def slug_date(slug):
    m = re.search(r"(\d{1,2})-([a-z]+)-(\d{4})", slug)
    if m and m.group(2)[:3] in MONTHS:
        return date(int(m.group(3)), MONTHS[m.group(2)[:3]], int(m.group(1)))
    m = re.search(r"([a-z]+)-(\d{1,2})-(\d{4})", slug)
    if m and m.group(1)[:3] in MONTHS:
        return date(int(m.group(3)), MONTHS[m.group(1)[:3]], int(m.group(2)))
    return None


def report_date(url):
    """The date in a report's file name: '...-as-of-16-July-2026-6PM.pdf'."""
    return slug_date(urllib.parse.unquote(url.rsplit("/", 1)[-1]).lower()) if url else None


def barangays_in(text):
    return sorted(set(re.findall(r"(?:Brgys?|Barangays?)\.?\s*(\d{1,3}(?:-?[A-Ca-c])?)\b", text)),
                  key=lambda b: (int(re.match(r"\d+", b).group()), b))


def more_barangays(text):
    """'Brgys. 275 and 286' / 'Barangays 667-A, 662, 671': every number after the word."""
    out = set()
    for run in re.findall(r"(?:Brgys?|Barangays?)\.?\s*((?:\d{1,3}(?:-?[A-Ca-c])?(?:\s*(?:,|and|&)\s*)?)+)", text):
        out.update(re.findall(r"\d{1,3}(?:-?[A-Ca-c])?", run))
    return sorted(out, key=lambda b: (int(re.match(r"\d+", b).group()), b))


def district_in(text):
    low = text.lower().replace(".", "")
    for d in DISTRICTS:
        if d in low:
            return {"sta cruz": "Santa Cruz", "sta ana": "Santa Ana", "sta mesa": "Santa Mesa"}.get(d, d.title())
    return ""


def latest_report(pdfs):
    """The terminal report if there is one, else the highest-numbered."""
    def rank(url):
        name = urllib.parse.unquote(url.rsplit("/", 1)[1])
        terminal = "terminal" in name.lower() or "final" in name.lower()
        number = re.search(r"Report[-_ ]?(?:No\.?)?[-_ ]?#?(\d+)", name, re.I)
        return (terminal, int(number.group(1)) if number else 0, name)
    reports = [u for u in pdfs if "DROMIC" in u.upper()]
    return max(reports, key=rank) if reports else None


def report_text(path):
    """The report's words on one line (PDF or Word). Many PDFs put every word
    on its own line, so whitespace is collapsed before searching."""
    try:
        if path.suffix.lower() == ".docx":
            import zipfile

            with zipfile.ZipFile(path) as z:
                xml = z.read("word/document.xml").decode("utf-8", "replace")
            raw = html.unescape(re.sub(r"<[^>]+>", "", re.sub(r"</w:p>|</w:tc>", " ", xml)))
        else:
            from pypdf import PdfReader

            raw = " ".join((p.extract_text() or "") for p in PdfReader(str(path)).pages)
    except Exception:  # noqa: BLE001 - an unreadable report is reported, not fatal
        return ""
    return " ".join(raw.split())


NEXT_PLACE = re.compile(
    r"\b(?:Caloocan|Las Pi[nñ]as|Makati|Malabon|Mandaluyong|Marikina|Muntinlupa|Navotas|Para[nñ]aque|Pasay|"
    r"Pasig|Pateros|Quezon City|San Juan|Taguig|Valenzuela|REGION|Region [IVX]+|CALABARZON|MIMAROPA|CAR\b|"
    r"BARMM|CARAGA|GRAND TOTAL|Note:|Source:)")


def manila_part(text):
    """The text after each 'City of Manila' / 'Manila City', up to the next
    city or region, joined."""
    parts = []
    for m in re.finditer(r"City of Manila|Manila City", text):
        rest = text[m.end(): m.end() + 2500]
        stop = NEXT_PLACE.search(rest)
        parts.append(rest[: stop.start()] if stop else rest[:600])
    return " | ".join(parts)


def collect_fires(posts):
    fires = [u for u in posts if "fire" in u.lower() and "manila" in u.lower()
             and not re.search(r"metro-manila|ncr|pasay|resorts", u.lower())]
    rows = []

    def one(url):
        title, pdfs = page(url)
        return url, title, pdfs

    with ThreadPoolExecutor(4) as pool:
        for url, title, pdfs in pool.map(one, fires):
            slug = url.rstrip("/").rsplit("/", 1)[1]
            report = latest_report(pdfs) or ""
            day = title_date(title) or slug_date(slug) or report_date(report)
            barangays = more_barangays(title) or barangays_in(title)
            rows.append({
                "incident_id": "DROMIC-" + slug[:60],
                "date": day.isoformat() if day else "",
                "hazard": "fire",
                "barangays": ";".join(barangays),
                "district": district_in(title),
                "title": title,
                "source_url": url,
                "report_pdf": report,
            })
    rows.sort(key=lambda r: (r["date"], r["incident_id"]))
    return rows


def collect_weather(posts):
    candidates = []
    for url in posts:
        slug = url.rstrip("/").rsplit("/", 1)[1]
        if WEATHER.search(slug) and not ELSEWHERE.search(slug) and "fire" not in slug:
            candidates.append(url)
    for url in posts:  # Manila's own flooding pages
        slug = url.rstrip("/").rsplit("/", 1)[1]
        if WEATHER.search(slug) and re.search(r"manila|ncr", slug) and url not in candidates:
            candidates.append(url)
    DOWNLOADS.mkdir(parents=True, exist_ok=True)
    rows = []
    downloaded = 0

    def one(url):
        try:
            title, pdfs = page(url)
        except Exception as e:  # noqa: BLE001 - one bad page is reported, not fatal
            return url, f"(page not read: {e})", None, None
        report = latest_report(pdfs)
        path = None
        if report:
            path = DOWNLOADS / urllib.parse.unquote(report.rsplit("/", 1)[1])
            if not path.exists():
                try:
                    path.write_bytes(get(report, binary=True))
                except Exception:  # noqa: BLE001 - a broken link leaves the event unread
                    path = None
        return url, title, report, path

    with ThreadPoolExecutor(4) as pool:
        for url, title, report, path in pool.map(one, candidates):
            slug = url.rstrip("/").rsplit("/", 1)[1]
            day = title_date(title) or slug_date(slug)
            text = report_text(path) if path else ""
            if path:
                downloaded += path.stat().st_size
            part = manila_part(text)
            rows.append({
                "event_id": "DROMIC-" + slug[:70],
                "start_date": day.isoformat() if day else "",
                "title": title,
                "manila_in_report": "yes" if part else ("no" if text else "unread"),
                "manila_barangays": ";".join(more_barangays(part)) if part else "",
                # The first figures after "City of Manila": usually barangays, families, persons affected.
                "manila_figures": " ".join(re.findall(r"[\d,]+(?:\.\d+)?", part)[:3]) if part else "",
                "source_url": url,
                "report_pdf": report or "",
            })
            print(f"{len(rows)}/{len(candidates)} {rows[-1]['start_date']} manila={rows[-1]['manila_in_report']}",
                  flush=True)
    rows.sort(key=lambda r: (r["start_date"], r["event_id"]))
    print(f"downloaded {downloaded / 1e6:.0f} MB of reports")
    return rows


def write(path, rows):
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    posts = all_posts()
    print(f"{len(posts)} DROMIC pages")
    fires = collect_fires(posts)
    write(DATA / "manila_fire_dromic.csv", fires)
    print(f"{len(fires)} Manila fires; {sum(1 for r in fires if r['barangays'])} with a barangay, "
          f"{sum(1 for r in fires if not r['date'])} without a date")
    if "--fires-only" in sys.argv:
        return
    events = collect_weather(posts)
    write(DATA / "manila_weather_events_dromic.csv", events)
    print(f"{len(events)} weather events; Manila in {sum(1 for r in events if r['manila_in_report'] == 'yes')}")


if __name__ == "__main__":
    main()
