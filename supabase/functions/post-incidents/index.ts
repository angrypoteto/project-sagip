// post-incidents: puts confirmed incidents on the MDRRMD Facebook Page
// (Joshua, 2026-10-13; migration incident_posts).
//
// The database keeps one post per flood, fire, or structural incident, with
// its words already written: what it is, the district, and the time.
// Nothing about who reported it, no barangay or address, never a medical
// emergency, never a simulated one. Since 2026-10-16 (migration
// incident_post_updates) the post follows the incident: it goes up marked
// unverified once a unit is sent, and the same post is then edited to
// confirmed, to a false alarm, or with a line when it is resolved. This
// function claims the queue with the service role, makes the post or edits
// the one already on the Page through the Graph API, and records what the
// Page accepted.
//
// It is separate from send-alerts so that function did not have to be
// redeployed; it uses the same Page secrets (FACEBOOK_PAGE_ID,
// FACEBOOK_PAGE_TOKEN, optional FACEBOOK_GRAPH_VERSION) and the same shared
// secret (ALERTS_SECRET, else the database's vault copy through
// sender_secret()), sent by the database as `x-sagip-key`.
//
// The database calls it when a post is queued (trigger on incident_post,
// through pg_net). A run with nothing queued does nothing.
//
// POST {"check": true} with the secret reports whether the Page is set up
// and sends nothing.
//
// Deploy with JWT checking off (the call uses the shared secret):
//   supabase functions deploy post-incidents --no-verify-jwt

const url = Deno.env.get("SUPABASE_URL");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function rpc<T>(name: string, params: Record<string, unknown> = {}): Promise<T> {
  const res = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: serviceKey!,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(params),
  });
  if (!res.ok) throw new Error(`${name}: HTTP ${res.status}`);
  const text = await res.text();
  return (text ? JSON.parse(text) : null) as T;
}

/** ALERTS_SECRET, or the database's vault copy (read once per instance). */
let vaultSecret: Promise<string | null> | undefined;
async function sharedSecret(): Promise<string | null> {
  const fromEnv = Deno.env.get("ALERTS_SECRET");
  if (fromEnv) return fromEnv;
  vaultSecret ??= rpc<string | null>("sender_secret").catch(() => {
    vaultSecret = undefined;
    return null;
  });
  return await vaultSecret;
}

/** The `x-sagip-key` header against the secret, in constant time. */
function authorized(headers: Headers, secret: string): boolean {
  const given = headers.get("x-sagip-key");
  if (!given || given.length !== secret.length) return false;
  let diff = 0;
  for (let i = 0; i < secret.length; i++) {
    diff |= given.charCodeAt(i) ^ secret.charCodeAt(i);
  }
  return diff === 0;
}

/** The Page and its token, or null when Facebook posting is not set up. */
function facebookPage(): { id: string; token: string } | null {
  const id = Deno.env.get("FACEBOOK_PAGE_ID");
  const token = Deno.env.get("FACEBOOK_PAGE_TOKEN");
  return id && token ? { id, token } : null;
}

type Outcome = {
  status: "sent" | "failed" | "notSetUp";
  detail: string | null;
  postId?: string;
};

/**
 * A new post on the Page, or an edit of [postId] when it is already there.
 * The token goes in the body and is never logged.
 */
async function postToFacebook(
  message: string,
  page: { id: string; token: string },
  postId: string | null,
): Promise<Outcome> {
  const version = Deno.env.get("FACEBOOK_GRAPH_VERSION") ?? "v24.0";
  const form = new URLSearchParams({ message, access_token: page.token });
  const target = postId ? encodeURIComponent(postId) : `${encodeURIComponent(page.id)}/feed`;
  try {
    const res = await fetch(`https://graph.facebook.com/${version}/${target}`, {
      method: "POST",
      body: form,
    });
    const body = await res.json().catch(() => null);
    const b = typeof body === "object" && body !== null ? body as Record<string, unknown> : {};
    if (res.ok && !postId && typeof b.id === "string") {
      return { status: "sent", detail: `post ${b.id}`, postId: b.id };
    }
    if (res.ok && postId && b.success === true) {
      return { status: "sent", detail: `edited post ${postId}`, postId };
    }
    const e = typeof b.error === "object" && b.error !== null ? b.error as Record<string, unknown> : {};
    const why = typeof e.message === "string" ? `: ${e.message.slice(0, 160)}` : "";
    return { status: "failed", detail: `Facebook refused the post (HTTP ${res.status})${why}` };
  } catch {
    return { status: "failed", detail: "Facebook could not be reached" };
  }
}

/** An incident's post, as claim_incident_posts() hands it over. */
type ClaimedPost = {
  post_id: number;
  incident_id: string;
  message: string;
  /** The post already on the Page, to edit; null for a new one. */
  fb_post_id?: string | null;
};

Deno.serve(async (req) => {
  if (!url || !serviceKey) return json(500, { error: "post-incidents is not set up" });
  const secret = await sharedSecret();
  if (!secret) return json(500, { error: "post-incidents is not set up" });
  if (!authorized(req.headers, secret)) return json(401, { error: "unauthorized" });

  const page = facebookPage();
  const request = await req.json().catch(() => null) as { check?: unknown } | null;
  if (request?.check === true) {
    // What is set up; nothing is claimed or sent. Names only, never values.
    return json(200, {
      facebook: page ? "page and token set" : "FACEBOOK_PAGE_ID or FACEBOOK_PAGE_TOKEN is not set",
      secret: Deno.env.get("ALERTS_SECRET") ? "ALERTS_SECRET" : "the database vault",
    });
  }

  let posts: ClaimedPost[];
  try {
    posts = (await rpc<ClaimedPost[]>("claim_incident_posts")) ?? [];
  } catch (e) {
    console.log(`post-incidents: could not claim posts (${(e as Error).message})`);
    return json(502, { error: "could not read the queue" });
  }

  const results: Record<string, string> = {};
  for (const p of posts) {
    const outcome: Outcome = page
      ? await postToFacebook(p.message, page, p.fb_post_id ?? null)
      : { status: "notSetUp", detail: "Facebook posting needs the page's access token" };
    // The words sent go back with the outcome: if the incident changed
    // meanwhile, the database queues the newer words as another edit.
    await rpc("record_incident_post", {
      p_post_id: p.post_id,
      p_status: outcome.status,
      p_detail: outcome.detail,
      p_fb_post_id: outcome.postId ?? null,
      p_message: p.message,
    }).catch(() => {});
    results[p.incident_id] = outcome.status;
    console.log(`post-incidents: ${p.incident_id} ${outcome.status}`);
  }
  return json(200, { processed: posts.length, results });
});
