// The Tier 2 SOS text message, the same codec as SosSms in
// packages/shared/lib/src/algorithms/sos_sms.dart (keep them in step; both
// are tested against packages/shared/test/fixtures/sos_sms_vectors.json).
//
//   SAGIP1 SOS <id> <lat>,<lng> <accuracy> <time> <flags> <crc>

export const PREFIX = "SAGIP1";

export interface SosSms {
  clientId: string;
  lat: number | null;
  lng: number | null;
  accuracyM: number | null;
  capturedAt: Date;
  mockLocation: boolean;
}

export type SosSmsProblem = "not_sagip" | "bad_checksum" | "bad_field";

export class SosSmsError extends Error {
  readonly reason: SosSmsProblem;
  constructor(reason: SosSmsProblem) {
    super(reason);
    this.reason = reason;
  }
}

/** CRC-16/CCITT-FALSE of the UTF-8 bytes, 4 uppercase hex digits. */
export function crc16Hex(text: string): string {
  let crc = 0xffff;
  for (const byte of new TextEncoder().encode(text)) {
    crc ^= byte << 8;
    for (let i = 0; i < 8; i++) {
      crc = (crc & 0x8000) !== 0 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff;
    }
  }
  return crc.toString(16).toUpperCase().padStart(4, "0");
}

export function encodeSosSms(s: SosSms): string {
  const body = [
    PREFIX,
    "SOS",
    s.clientId.replaceAll("-", "").toLowerCase(),
    s.lat === null || s.lng === null ? "-" : `${s.lat.toFixed(5)},${s.lng.toFixed(5)}`,
    s.lat === null || s.accuracyM === null ? "-" : `${Math.round(s.accuracyM)}`,
    `${Math.floor(s.capturedAt.getTime() / 1000)}`,
    s.mockLocation ? "M" : "-",
  ].join(" ");
  return `${body} ${crc16Hex(body)}`;
}

export function decodeSosSms(text: string): SosSms {
  const parts = text.trim().split(/\s+/);
  if (parts.length !== 8 || parts[0] !== PREFIX || parts[1] !== "SOS") {
    throw new SosSmsError("not_sagip");
  }
  const body = parts.slice(0, 7).join(" ");
  if (parts[7].toUpperCase() !== crc16Hex(body)) {
    throw new SosSmsError("bad_checksum");
  }
  const id = parts[2].toLowerCase();
  if (!/^[0-9a-f]{32}$/.test(id)) throw new SosSmsError("bad_field");

  let lat: number | null = null;
  let lng: number | null = null;
  if (parts[3] !== "-") {
    const ll = parts[3].split(",");
    lat = ll.length === 2 ? Number(ll[0]) : NaN;
    lng = ll.length === 2 ? Number(ll[1]) : NaN;
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
      throw new SosSmsError("bad_field");
    }
  }
  let accuracyM: number | null = null;
  if (parts[4] !== "-") {
    if (!/^\d{1,6}$/.test(parts[4]) || Number(parts[4]) > 100000) throw new SosSmsError("bad_field");
    accuracyM = Number(parts[4]);
  }
  if (!/^\d{1,12}$/.test(parts[5]) || Number(parts[5]) <= 0) throw new SosSmsError("bad_field");
  if (parts[6] !== "M" && parts[6] !== "-") throw new SosSmsError("bad_field");

  return {
    clientId: `${id.slice(0, 8)}-${id.slice(8, 12)}-${id.slice(12, 16)}-${id.slice(16, 20)}-${id.slice(20)}`,
    lat,
    lng,
    accuracyM,
    capturedAt: new Date(Number(parts[5]) * 1000),
    mockLocation: parts[6] === "M",
  };
}
