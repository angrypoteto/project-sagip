// One run of the PAGASA feed: read the two pages (and the latest bulletin
// when a cyclone is active), record Manila's readings, and record how each
// source went. The database decides whether the readings changed and, if
// so, the threshold engine raises or ends alerts (FR5).

import {
  type BulletinPage,
  type CycloneReading,
  parseBulletinPage,
  parseCycloneBulletin,
  parseRainfallWarning,
  type RainfallReading,
} from "./pagasa.ts";

export const ncrPage = "https://bagong.pagasa.dost.gov.ph/regional-forecast/ncrprsd";
export const bulletinPage =
  "https://bagong.pagasa.dost.gov.ph/tropical-cyclone/severe-weather-bulletin";

/** A clear name for PAGASA's logs; one request per page per run. */
export const userAgent =
  "SAGIP-MDRRMD/1.0 (Manila City emergency response capstone; reads public bulletins every 10 minutes)";

export interface IngestDeps {
  /** GET a page as text; throws on a non-200 answer. */
  getText(url: string): Promise<string>;
  /** GET a file as bytes; throws on a non-200 answer. */
  getBytes(url: string): Promise<Uint8Array>;
  /** The text of a PDF, pages in order. */
  pdfText(bytes: Uint8Array): Promise<string>;
  rpc<T>(name: string, params: Record<string, unknown>): Promise<T>;
}

export type SourceResult<T> =
  | { ok: true; reading: T }
  | { ok: false; error: string };

export interface IngestSummary {
  rainfall: SourceResult<RainfallReading>;
  cyclone: SourceResult<{ page: BulletinPage; bulletin?: CycloneReading }>;
  /** What the database did with the readings, or null when none was read. */
  recorded: string | null;
}

const message = (e: unknown) =>
  (e instanceof Error ? e.message : String(e)).slice(0, 300);

async function readRainfall(deps: IngestDeps): Promise<SourceResult<RainfallReading>> {
  try {
    const reading = parseRainfallWarning(await deps.getText(ncrPage));
    return reading.state === "unreadable"
      ? { ok: false, error: reading.reason }
      : { ok: true, reading };
  } catch (e) {
    return { ok: false, error: message(e) };
  }
}

async function readCyclone(
  deps: IngestDeps,
): Promise<SourceResult<{ page: BulletinPage; bulletin?: CycloneReading }>> {
  try {
    const page = parseBulletinPage(await deps.getText(bulletinPage), bulletinPage);
    if (page.state === "unreadable") return { ok: false, error: page.reason };
    if (page.state === "none") return { ok: true, reading: { page } };
    const bulletin = parseCycloneBulletin(
      await deps.pdfText(await deps.getBytes(page.pdfUrl)),
    );
    return bulletin.state === "unreadable"
      ? { ok: false, error: bulletin.reason }
      : { ok: true, reading: { page, bulletin } };
  } catch (e) {
    return { ok: false, error: message(e) };
  }
}

export async function ingest(deps: IngestDeps): Promise<IngestSummary> {
  const [rainfall, cyclone] = await Promise.all([readRainfall(deps), readCyclone(deps)]);

  const rain = rainfall.ok && rainfall.reading.state !== "unreadable"
    ? rainfall.reading.mmPerHour
    : null;
  const tc = cyclone.ok
    ? cyclone.reading.bulletin?.state === "bulletin"
      ? cyclone.reading.bulletin
      : { signal: 0, surgeM: 0 }
    : null;

  let recorded: string | null = null;
  if (rain !== null || tc !== null) {
    // Null means "could not read": the database keeps the last value.
    recorded = await deps.rpc<string>("record_pagasa_reading", {
      p_rainfall: rain,
      p_signal: tc?.signal ?? null,
      p_surge_m: tc?.surgeM ?? null,
    });
  }

  await deps.rpc("record_feed_status", {
    p_source: "pagasa_rainfall",
    p_ok: rainfall.ok,
    p_error: rainfall.ok ? null : rainfall.error,
    p_seen: rainfall.ok ? rainfall.reading : null,
  });
  await deps.rpc("record_feed_status", {
    p_source: "pagasa_cyclone",
    p_ok: cyclone.ok,
    p_error: cyclone.ok ? null : cyclone.error,
    p_seen: cyclone.ok
      ? cyclone.reading.bulletin ?? { state: cyclone.reading.page.state }
      : null,
  });

  return { rainfall, cyclone, recorded };
}
