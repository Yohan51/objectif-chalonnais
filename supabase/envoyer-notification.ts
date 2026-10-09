// =====================================================================
// Fonction Supabase « envoyer-notification » — L'Objectif Châlonnais
// À coller tel quel dans Supabase : Edge Functions → Deploy a new function
// → Via Editor, nom : envoyer-notification
//
// Secrets nécessaires (Edge Functions → Secrets) :
//   VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT
// Le code demandé pour envoyer est le CODE MODÉRATEUR (vérifié par la base,
// voir supabase/alertes-code.sql). L'ancien secret CODE_ENVOI, s'il existe
// encore, reste accepté.
// =====================================================================

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ---------- Outils base64url ----------
function b64uToBytes(s: string): Uint8Array {
  s = s.replace(/-/g, "+").replace(/_/g, "/");
  while (s.length % 4) s += "=";
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
function bytesToB64u(b: Uint8Array): string {
  let bin = "";
  for (let i = 0; i < b.length; i++) bin += String.fromCharCode(b[i]);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function concat(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0;
  for (const p of parts) { out.set(p, o); o += p.length; }
  return out;
}
const enc = new TextEncoder();

async function hmac(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const k = await crypto.subtle.importKey("raw", key, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", k, data));
}

// ---------- Signature VAPID (JWT ES256) ----------
export async function vapidHeader(endpoint: string, publicKey: string, privateKey: string, subject: string) {
  const pub = b64uToBytes(publicKey);
  const jwk = {
    kty: "EC", crv: "P-256",
    x: bytesToB64u(pub.slice(1, 33)),
    y: bytesToB64u(pub.slice(33, 65)),
    d: privateKey,
  };
  const key = await crypto.subtle.importKey("jwk", jwk, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = bytesToB64u(enc.encode(JSON.stringify({ typ: "JWT", alg: "ES256" })));
  const claims = bytesToB64u(enc.encode(JSON.stringify({
    aud: new URL(endpoint).origin,
    exp: Math.floor(Date.now() / 1000) + 12 * 3600,
    sub: subject,
  })));
  const unsigned = `${header}.${claims}`;
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(unsigned)));
  return `vapid t=${unsigned}.${bytesToB64u(sig)}, k=${publicKey}`;
}

// ---------- Chiffrement du message (RFC 8291, aes128gcm) ----------
export async function encryptPayload(payload: string, p256dh: string, auth: string): Promise<Uint8Array> {
  const uaPublic = b64uToBytes(p256dh);
  const authSecret = b64uToBytes(auth);

  const local = await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]);
  const asPublic = new Uint8Array(await crypto.subtle.exportKey("raw", local.publicKey));
  const uaKey = await crypto.subtle.importKey("raw", uaPublic, { name: "ECDH", namedCurve: "P-256" }, false, []);
  const ecdhSecret = new Uint8Array(await crypto.subtle.deriveBits({ name: "ECDH", public: uaKey }, local.privateKey, 256));

  const prkKey = await hmac(authSecret, ecdhSecret);
  const keyInfo = concat(enc.encode("WebPush: info\0"), uaPublic, asPublic, new Uint8Array([1]));
  const ikm = await hmac(prkKey, keyInfo);

  const salt = crypto.getRandomValues(new Uint8Array(16));
  const prk = await hmac(salt, ikm);
  const cek = (await hmac(prk, concat(enc.encode("Content-Encoding: aes128gcm\0"), new Uint8Array([1])))).slice(0, 16);
  const nonce = (await hmac(prk, concat(enc.encode("Content-Encoding: nonce\0"), new Uint8Array([1])))).slice(0, 12);

  const aesKey = await crypto.subtle.importKey("raw", cek, { name: "AES-GCM" }, false, ["encrypt"]);
  const plaintext = concat(enc.encode(payload), new Uint8Array([2]));
  const cipher = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, aesKey, plaintext));

  const header = new Uint8Array(16 + 4 + 1 + asPublic.length);
  header.set(salt, 0);
  new DataView(header.buffer).setUint32(16, 4096);
  header[20] = asPublic.length;
  header.set(asPublic, 21);
  return concat(header, cipher);
}

// ---------- Service ----------
type Sub = { endpoint: string; p256dh: string; auth: string };

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}

if (typeof Deno !== "undefined" && Deno.serve) Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ erreur: "Méthode non autorisée" }, 405);

  const env = (k: string) => Deno.env.get(k) || "";
  const VAPID_PUBLIC = env("VAPID_PUBLIC_KEY");
  const VAPID_PRIVATE = env("VAPID_PRIVATE_KEY");
  const SUBJECT = env("VAPID_SUBJECT") || "mailto:lobjectifchalonnais@gmail.com";
  const ANCIEN_CODE = env("CODE_ENVOI");
  const SB_URL = env("SUPABASE_URL");
  const SB_KEY = env("SERVICE_KEY") || env("SUPABASE_SERVICE_ROLE_KEY");
  if (!VAPID_PUBLIC || !VAPID_PRIVATE) return json({ erreur: "Secrets manquants dans Supabase (VAPID)." }, 500);
  if (!SB_URL || !SB_KEY) return json({ erreur: "Clé d'accès à la base introuvable (ajoute le secret SERVICE_KEY)." }, 500);

  const dbHeaders: Record<string, string> = { apikey: SB_KEY };
  if (SB_KEY.startsWith("eyJ")) dbHeaders.Authorization = `Bearer ${SB_KEY}`;

  let data: { code?: string; titre?: string; message?: string; lien?: string; endpoint?: string };
  try { data = await req.json(); } catch { return json({ erreur: "Requête illisible." }, 400); }

  // Vérification du code modérateur par la base (8 essais ratés = blocage 15 minutes)
  const code = (data.code || "").trim();
  let codeOk = !!ANCIEN_CODE && code === ANCIEN_CODE;
  if (!codeOk && code) {
    const ip = (req.headers.get("cf-connecting-ip") || (req.headers.get("x-forwarded-for") || "").split(",")[0] || "").trim();
    const v = await fetch(`${SB_URL}/rest/v1/rpc/oc_verifier_code_serveur`, {
      method: "POST",
      headers: { ...dbHeaders, "Content-Type": "application/json" },
      body: JSON.stringify({ p_code: code, p_ip: ip }),
    });
    if (!v.ok) return json({ erreur: "Vérification du code impossible : as-tu bien exécuté alertes-code.sql dans Supabase ?" }, 500);
    codeOk = (await v.json()) === true;
  }
  if (!codeOk) return json({ erreur: "Code modérateur incorrect (après 8 essais ratés, l'accès est bloqué 15 minutes)." }, 403);

  const titre = (data.titre || "").trim().slice(0, 80);
  const message = (data.message || "").trim().slice(0, 240);
  if (!titre) return json({ erreur: "Le titre est obligatoire." }, 400);

  let subs: Sub[];
  if (data.endpoint) {
    subs = [{ ...(await (await fetch(`${SB_URL}/rest/v1/push_subscriptions?select=endpoint,p256dh,auth&endpoint=eq.${encodeURIComponent(data.endpoint)}`, { headers: dbHeaders })).json())[0] }]
      .filter((s) => s.endpoint);
  } else {
    const r = await fetch(`${SB_URL}/rest/v1/push_subscriptions?select=endpoint,p256dh,auth`, { headers: dbHeaders });
    if (!r.ok) return json({ erreur: `Lecture des abonnés impossible (${r.status}).` }, 500);
    subs = await r.json();
  }
  if (!subs.length) return json({ envoyes: 0, echecs: 0, supprimes: 0, note: "Aucun abonné pour l'instant." });

  const payload = JSON.stringify({ titre, message, lien: data.lien || "./" });
  let envoyes = 0, echecs = 0, supprimes = 0;

  const sendOne = async (s: Sub) => {
    try {
      const body = await encryptPayload(payload, s.p256dh, s.auth);
      const res = await fetch(s.endpoint, {
        method: "POST",
        headers: {
          Authorization: await vapidHeader(s.endpoint, VAPID_PUBLIC, VAPID_PRIVATE, SUBJECT),
          "Content-Encoding": "aes128gcm",
          "Content-Type": "application/octet-stream",
          TTL: "86400",
          Urgency: "normal",
        },
        body,
      });
      if (res.status === 404 || res.status === 410) {
        await fetch(`${SB_URL}/rest/v1/push_subscriptions?endpoint=eq.${encodeURIComponent(s.endpoint)}`, { method: "DELETE", headers: dbHeaders });
        supprimes++;
      } else if (res.ok) envoyes++;
      else echecs++;
    } catch { echecs++; }
  };

  for (let i = 0; i < subs.length; i += 50) await Promise.all(subs.slice(i, i + 50).map(sendOne));
  return json({ envoyes, echecs, supprimes });
});
