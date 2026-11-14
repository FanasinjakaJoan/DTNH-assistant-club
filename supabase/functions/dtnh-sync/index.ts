// DTNH Assistant Club — Edge Function de synchronisation (v3).
//
// Reçoit le même contrat que le webhook Google Apps Script (action + secret +
// items nommés) mais écrit dans PostgreSQL (Supabase).
//
// Deux modes d'authentification, cumulables :
//   1. **Session Google** (`X-DTNH-Auth: Bearer <jwt>`) : identité vérifiée,
//      l'`author_id` de chaque ligne est rattaché à `auth.uid()`. C'est le mode
//      privilégié dès qu'un membre est connecté.
//   2. **Secret partagé** (~48 hex, `DTNH_SHARED_SECRET`) : mode hors-ligne
//      historique, conservé pour que l'application reste utilisable sans compte.
//
// Une requête est acceptée si l'un des deux est valide. `verify_jwt` reste
// désactivé : les navigateurs envoient le jeton dans un en-tête personnalisé
// (pas via `Authorization`, réservé au préflight `apikey`).
//
// Déploiement : fonctions Supabase, slug `dtnh-sync`.

const SHARED_SECRET = Deno.env.get("DTNH_SHARED_SECRET") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  Deno.env.get("SUPABASE_SECRET_KEY") ??
  "";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-dtnh-auth",
  "Access-Control-Max-Age": "86400",
};

interface SyncItem {
  id?: string;
  entity?: string;
  sheet?: string;
  operation?: string;
  data?: Record<string, unknown>;
}

interface SyncPayload {
  action?: string;
  secret?: string;
  deviceId?: string;
  batchId?: string;
  sentAt?: string;
  items?: SyncItem[];
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json; charset=utf-8" },
  });
}

function str(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  const text = String(value).trim();
  return text === "" ? null : text;
}

function num(value: unknown): number | null {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function bool(value: unknown, fallback: boolean): boolean {
  if (typeof value === "boolean") return value;
  if (value === "true" || value === "1" || value === 1) return true;
  if (value === "false" || value === "0" || value === 0) return false;
  return fallback;
}

function dateOnly(value: unknown): string | null {
  const text = str(value);
  if (!text) return null;
  const iso = text.match(/^(\d{4}-\d{2}-\d{2})/);
  return iso ? iso[1] : null;
}

function isoDate(value: unknown): string | null {
  const text = str(value);
  if (!text) return null;
  const parsed = new Date(text);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

function dbHeaders(extra: Record<string, string> = {}): Record<string, string> {
  return {
    apikey: SERVICE_KEY,
    Authorization: `Bearer ${SERVICE_KEY}`,
    "Content-Type": "application/json",
    ...extra,
  };
}

/**
 * Vérifie le JWT présenté et renvoie l'identifiant Supabase (`sub`), ou `null`.
 * On interroge `/auth/v1/user` : la vérification de signature et d'expiration
 * reste faite par Supabase, jamais par ce code.
 */
async function resolveUser(token: string): Promise<{ id: string; email: string | null } | null> {
  try {
    const response = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${token}` },
    });
    if (!response.ok) return null;
    const user = await response.json();
    const id = str(user?.id);
    if (!id) return null;
    return { id, email: str(user?.email) };
  } catch {
    return null;
  }
}

/** UPSERT idempotent : les ids sont des UUID générés par l'application. */
async function upsert(
  table: string,
  rows: Record<string, unknown>[],
  conflictColumn: string,
): Promise<number> {
  if (rows.length === 0) return 0;
  const response = await fetch(
    `${SUPABASE_URL}/rest/v1/${table}?on_conflict=${conflictColumn}`,
    {
      method: "POST",
      headers: dbHeaders({ Prefer: "resolution=merge-duplicates,return=minimal" }),
      body: JSON.stringify(rows),
    },
  );
  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`${table}: HTTP ${response.status} ${detail.slice(0, 300)}`);
  }
  return rows.length;
}

function mapAttendance(
  data: Record<string, unknown>,
  userId: string | null,
): Record<string, unknown> | null {
  const id = str(data.id);
  const sessionDate = dateOnly(data.date);
  if (!id || !sessionDate) return null;
  return {
    id,
    session_id: str(data.sessionId) ?? `${sessionDate}#${str(data.categorie) ?? "NA"}`,
    session_date: sessionDate,
    recorded_at: isoDate(data.updatedAt) ?? `${sessionDate}T${str(data.heure) ?? "00:00"}:00Z`,
    category: str(data.categorie) ?? "NA",
    player_id: str(data.joueurId) ?? "unknown",
    player_name: str(data.joueur) ?? "Inconnu",
    jersey_number: num(data.numero),
    status: str(data.statut) ?? "ABSENT",
    // Identité : compte Google vérifié > identifiant local envoyé par l'app.
    author_id: userId ?? str(data.auteurId) ?? "unknown",
    author_name: str(data.auteur) ?? "Inconnu",
    note: str(data.note),
    updated_at: isoDate(data.updatedAt) ?? new Date().toISOString(),
    synced_at: new Date().toISOString(),
  };
}

function mapTransaction(
  data: Record<string, unknown>,
  userId: string | null,
): Record<string, unknown> | null {
  const id = str(data.id);
  const date = dateOnly(data.date);
  if (!id || !date) return null;
  return {
    id,
    date,
    flow: str(data.flux) ?? "OUT",
    category: str(data.categorie) ?? "AUTRE_SORTIE",
    amount: num(data.montant) ?? 0,
    payment_method: str(data.modePaiement) ?? "ESPECES",
    details: str(data.details),
    player_name: str(data.joueur),
    staff_name: str(data.staff),
    event_name: str(data.evenement),
    period_month: str(data.mois),
    author_id: userId ?? str(data.auteurId) ?? "unknown",
    author_name: str(data.auteur) ?? "Inconnu",
    created_at: isoDate(data.createdAt) ?? new Date().toISOString(),
    updated_at: isoDate(data.updatedAt) ?? new Date().toISOString(),
    synced_at: new Date().toISOString(),
  };
}

function mapPlayer(
  data: Record<string, unknown>,
  userId: string | null,
): Record<string, unknown> | null {
  const id = str(data.id);
  const name = str(data.nom);
  if (!id || !name) return null;
  return {
    id,
    full_name: name,
    category: str(data.categorie) ?? "NA",
    jersey_number: num(data.numero),
    phone: str(data.telephone),
    is_active: bool(data.actif, true),
    created_at: isoDate(data.createdAt) ?? new Date().toISOString(),
    updated_at: isoDate(data.updatedAt) ?? new Date().toISOString(),
    // Renseigné quand le joueur est créé par un membre connecté : sert de base
    // aux politiques RLS par propriétaire.
    owner_id: userId,
  };
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (request.method !== "POST") {
    return json({ ok: false, message: "Utilisez une requête POST." }, 405);
  }
  if (!SUPABASE_URL || !SERVICE_KEY) {
    return json({ ok: false, message: "Configuration Supabase incomplète." }, 500);
  }

  let payload: SyncPayload;
  try {
    payload = await request.json();
  } catch {
    return json({ ok: false, message: "Corps JSON invalide." }, 400);
  }

  // --- Authentification : session Google d'abord, secret partagé ensuite ----
  const authHeader = request.headers.get("x-dtnh-auth") ?? "";
  const bearer = authHeader.toLowerCase().startsWith("bearer ")
    ? authHeader.slice(7).trim()
    : "";
  const user = bearer ? await resolveUser(bearer) : null;

  const secretOk =
    SHARED_SECRET !== "" && (payload.secret ?? "") === SHARED_SECRET;

  if (!user && !secretOk) {
    if (!SHARED_SECRET) {
      return json(
        { ok: false, message: "DTNH_SHARED_SECRET n'est pas configuré et aucune session valide n'a été présentée." },
        500,
      );
    }
    return json(
      {
        ok: false,
        message: bearer
          ? "Session Google invalide ou expirée, et secret partagé incorrect."
          : "Secret invalide.",
      },
      401,
    );
  }

  const userId = user?.id ?? null;
  const identity = user ? "google" : "secret";
  const action = (payload.action ?? "push").toLowerCase();
  const serverTime = new Date().toISOString();

  if (action === "ping") {
    return json({
      ok: true,
      message: user
        ? `Supabase connecté (DTNH) — compte ${user.email ?? user.id}.`
        : "Supabase connecté (DTNH).",
      serverTime,
      target: "supabase",
      identity,
      userId,
      tables: ["dtnh_players", "dtnh_attendance", "dtnh_transactions"],
    });
  }

  if (action !== "push") {
    return json({ ok: false, message: `Action inconnue : ${action}` }, 400);
  }

  const items = Array.isArray(payload.items) ? payload.items : [];
  if (items.length === 0) {
    return json({ ok: false, message: "Aucun élément à synchroniser." }, 400);
  }

  const results: Array<Record<string, unknown>> = [];
  const buckets: Record<string, Record<string, unknown>[]> = {
    players: [],
    attendance: [],
    transactions: [],
  };

  for (const item of items) {
    const id = str(item.id);
    const entity = str(item.entity) ?? "";
    const data = (item.data ?? {}) as Record<string, unknown>;

    if (!id) {
      results.push({ id, status: "error", error: "Identifiant manquant" });
      continue;
    }

    // Suppression logique : on archive le joueur (les autres entités ne sont
    // jamais supprimées côté serveur, l'historique reste consultable).
    if ((item.operation ?? "upsert").toLowerCase() === "delete") {
      if (entity === "player") {
        buckets.players.push({
          id,
          full_name: str(data.nom) ?? "Joueur archivé",
          category: str(data.categorie) ?? "NA",
          is_active: false,
          updated_at: new Date().toISOString(),
        });
        results.push({ id, status: "ok" });
      } else {
        results.push({ id, status: "ok", note: "Suppression locale uniquement" });
      }
      continue;
    }

    try {
      if (entity === "attendance") {
        const row = mapAttendance(data, userId);
        if (!row) throw new Error("Champs obligatoires manquants (id, date)");
        buckets.attendance.push(row);
      } else if (entity === "transaction") {
        const row = mapTransaction(data, userId);
        if (!row) throw new Error("Champs obligatoires manquants (id, date)");
        buckets.transactions.push(row);
      } else if (entity === "player") {
        const row = mapPlayer(data, userId);
        if (!row) throw new Error("Champs obligatoires manquants (id, nom)");
        buckets.players.push(row);
      } else {
        throw new Error(`Entité inconnue : ${entity}`);
      }
      results.push({ id, status: "ok" });
    } catch (error) {
      results.push({
        id,
        status: "error",
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  try {
    await upsert("dtnh_players", buckets.players, "id");
    await upsert("dtnh_attendance", buckets.attendance, "id");
    await upsert("dtnh_transactions", buckets.transactions, "id");

    await fetch(`${SUPABASE_URL}/rest/v1/dtnh_sync_log`, {
      method: "POST",
      headers: dbHeaders({ Prefer: "return=minimal" }),
      body: JSON.stringify({
        batch_id: str(payload.batchId),
        device_id: str(payload.deviceId),
        action,
        item_count: items.length,
        user_id: userId,
      }),
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return json({ ok: false, message: `Écriture Supabase impossible : ${message}` }, 502);
  }

  return json({
    ok: true,
    message: "Lot enregistré dans Supabase.",
    serverTime,
    identity,
    results,
  });
});
