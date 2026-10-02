// Push through Firebase Cloud Messaging (HTTP v1). Pure helpers plus the two
// network calls, which take `fetch` as a parameter so the tests can stand
// it in. Tested with Node (fcm.test.ts and index.test.ts).
//
// The sender authenticates with a Firebase service account (the JSON key
// file from the Firebase console, stored whole as the FIREBASE_SERVICE_ACCOUNT
// secret). It signs a short-lived JWT with the account's private key and
// trades it for an access token, as Google's OAuth 2.0 service-account flow
// describes; no Google library is needed.

/** The fields of the service account key file that the sender uses. */
export interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri: string;
}

/** Reads the secret; null when it is missing or not a service account key. */
export function parseServiceAccount(json: string | undefined | null): ServiceAccount | null {
  if (!json) return null;
  try {
    const v = JSON.parse(json);
    if (
      typeof v?.project_id !== "string" || typeof v?.client_email !== "string" ||
      typeof v?.private_key !== "string" || !v.private_key.includes("PRIVATE KEY")
    ) return null;
    return {
      project_id: v.project_id,
      client_email: v.client_email,
      private_key: v.private_key,
      token_uri: typeof v.token_uri === "string" ? v.token_uri : "https://oauth2.googleapis.com/token",
    };
  } catch {
    return null;
  }
}

const scope = "https://www.googleapis.com/auth/firebase.messaging";

function base64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64urlText(text: string): string {
  return base64url(new TextEncoder().encode(text));
}

/** The DER bytes inside a PEM "PRIVATE KEY" block. */
export function pemToDer(pem: string): ArrayBuffer {
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\\n/g, "").replace(/\s+/g, "");
  const raw = atob(body);
  const out = new Uint8Array(new ArrayBuffer(raw.length));
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out.buffer;
}

/** The signed assertion for the token request (RS256, valid one hour). */
export async function signedAssertion(sa: ServiceAccount, nowSeconds: number): Promise<string> {
  const header = base64urlText(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64urlText(JSON.stringify({
    iss: sa.client_email,
    scope,
    aud: sa.token_uri,
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  }));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  return `${header}.${claims}.${base64url(new Uint8Array(signature))}`;
}

/** An access token for FCM. Throws when Google refuses the key. */
export async function accessToken(
  sa: ServiceAccount,
  fetchFn: typeof fetch,
  nowSeconds = Math.floor(Date.now() / 1000),
): Promise<string> {
  const res = await fetchFn(sa.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: await signedAssertion(sa, nowSeconds),
    }),
  });
  const body = await res.json().catch(() => null) as { access_token?: unknown } | null;
  if (!res.ok || typeof body?.access_token !== "string") {
    throw new Error(`Firebase sign-in refused (HTTP ${res.status})`);
  }
  return body.access_token;
}

// ------------------------------------------------------------ topics

/** Every resident's phone is subscribed to this topic. */
export const allManilaTopic = "manila";

const accents: Record<string, string> = {
  "á": "a", "à": "a", "â": "a", "ä": "a", "ã": "a",
  "é": "e", "è": "e", "ê": "e", "ë": "e",
  "í": "i", "ì": "i", "î": "i", "ï": "i",
  "ó": "o", "ò": "o", "ô": "o", "ö": "o", "õ": "o",
  "ú": "u", "ù": "u", "û": "u", "ü": "u",
  "ñ": "n", "ç": "c",
};

/**
 * The FCM topic of one barangay ("Barangay 412" -> "area-barangay-412").
 * Must match `pushTopicForBarangay` in packages/shared (same test vectors).
 */
export function topicForBarangay(barangay: string): string {
  const slug = [...barangay.toLowerCase()]
    .map((c) => accents[c] ?? c)
    .join("")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return `area-${slug || "unknown"}`;
}

/**
 * Where an alert goes: the all-Manila topic, or conditions over the
 * barangays' topics, at most five topics each (FCM's limit).
 */
export function alertTargets(barangays: string[]): Target[] {
  const topics = [...new Set(barangays.map(topicForBarangay))].sort();
  if (topics.length === 0) return [{ topic: allManilaTopic }];
  const out: Target[] = [];
  for (let i = 0; i < topics.length; i += 5) {
    const group = topics.slice(i, i + 5);
    out.push(group.length === 1 ? { topic: group[0] } : {
      condition: group.map((t) => `'${t}' in topics`).join(" || "),
    });
  }
  return out;
}

// ------------------------------------------------------------ messages

export type Target = { token: string } | { topic: string } | { condition: string };

/** Android notification channels the app creates (MainActivity.kt). */
export const channels = {
  alert: "sagip_alerts",
  rescue: "sagip_rescue",
  assignment: "sagip_assignments",
} as const;

/** One FCM v1 message: shown by Android even when the app is closed. */
export function fcmMessage(
  target: Target,
  title: string,
  body: string,
  data: Record<string, unknown>,
  channel: string,
): Record<string, unknown> {
  const strings: Record<string, string> = {};
  for (const [k, v] of Object.entries(data)) {
    if (v !== null && v !== undefined) strings[k] = String(v);
  }
  return {
    message: {
      ...target,
      notification: { title, body: body.length > 500 ? `${body.slice(0, 499)}…` : body },
      data: strings,
      android: {
        priority: "high",
        notification: { channel_id: channel },
      },
    },
  };
}

/** What FCM said about one message. */
export interface SendResult {
  ok: boolean;
  /** The token no longer exists or belongs to another project: stop using it. */
  stale: boolean;
  detail: string | null;
}

/** FCM's error code for a token that should be dropped, from its error body. */
export function isStaleToken(status: number, body: unknown): boolean {
  if (status !== 404 && status !== 403 && status !== 400) return false;
  const details = (body as { error?: { details?: unknown[] } } | null)?.error?.details ?? [];
  return details.some((d) =>
    /^(UNREGISTERED|SENDER_ID_MISMATCH)$/.test(String((d as Record<string, unknown>)?.errorCode ?? ""))
  );
}

/** Sends one message. Never throws: a network error is a failed send. */
export async function sendMessage(
  projectId: string,
  token: string,
  message: Record<string, unknown>,
  fetchFn: typeof fetch,
): Promise<SendResult> {
  try {
    const res = await fetchFn(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify(message),
    });
    if (res.ok) return { ok: true, stale: false, detail: null };
    const body = await res.json().catch(() => null);
    return { ok: false, stale: isStaleToken(res.status, body), detail: `HTTP ${res.status}` };
  } catch {
    return { ok: false, stale: false, detail: "FCM could not be reached" };
  }
}
