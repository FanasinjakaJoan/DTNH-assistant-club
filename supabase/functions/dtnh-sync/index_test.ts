/**
 * ============================================================================
 *  Tests locaux de l'Edge Function `dtnh-sync` — sans Supabase, sans réseau
 * ============================================================================
 *  Le mapping des lignes (JSON nommé -> colonnes PostgreSQL) est le point où
 *  une régression est la plus coûteuse : elle n'apparaît qu'au moment de
 *  l'écriture réelle, côté serveur. On teste donc ces fonctions pures ici.
 *
 *  Usage :  deno test supabase/functions/dtnh-sync/
 *  Sortie : code 0 si tout passe, 1 sinon (utilisable en CI).
 * ============================================================================
 */
import {
  mapAttendance,
  mapPlayer,
  mapTransaction,
} from "./index.ts";
import { assertEquals, assert } from "jsr:@std/assert@1";

Deno.test("mapPlayer : la date de naissance devient birth_date", () => {
  const row = mapPlayer(
    {
      id: "p-1",
      nom: "Rakoto Jean",
      categorie: "U16",
      dateNaissance: "2010-04-17",
      numero: 7,
      telephone: "0340000000",
      actif: true,
      createdAt: "2026-11-05T08:00:00.000Z",
      updatedAt: "2026-11-05T08:00:00.000Z",
    },
    null,
  );
  assertEquals(row?.birth_date, "2010-04-17");
  assertEquals(row?.jersey_number, 7);
  assertEquals(row?.is_active, true);
});

Deno.test("mapPlayer : date de naissance absente -> null", () => {
  const row = mapPlayer(
    { id: "p-2", nom: "Sans Date", categorie: "U12" },
    null,
  );
  assertEquals(row?.birth_date, null);
});

Deno.test("mapPlayer : date partielle rejetée, jamais inventée", () => {
  // `dateOnly` n'accepte que `yyyy-MM-dd` : une saisie libre ne doit pas
  // produire une date approximative en base.
  const row = mapPlayer(
    { id: "p-3", nom: "Partiel", categorie: "U12", dateNaissance: "17/04/2010" },
    null,
  );
  assertEquals(row?.birth_date, null);
});

Deno.test("mapPlayer : identifiant et nom obligatoires", () => {
  assertEquals(mapPlayer({ nom: "Sans ID" }, null), null);
  assertEquals(mapPlayer({ id: "p-4" }, null), null);
});

Deno.test("mapPlayer : owner_id suit la session fournie", () => {
  const row = mapPlayer(
    { id: "p-5", nom: "Membre", categorie: "U16" },
    "user-uuid",
  );
  assertEquals(row?.owner_id, "user-uuid");
});

Deno.test("mapAttendance : champs de traçabilité conservés", () => {
  const row = mapAttendance(
    {
      id: "a-1",
      date: "2026-11-05",
      categorie: "U16",
      joueur: "Rakoto Jean",
      statut: "Présent",
      auteur: "Coach Naina",
      heure: "16:30",
      joueurId: "p-1",
      sessionId: "s-1",
      numero: 7,
      auteurId: "local-author",
      updatedAt: "2026-11-05T16:30:00.000Z",
    },
    null,
  );
  assertEquals(row?.session_date, "2026-11-05");
  assertEquals(row?.player_name, "Rakoto Jean");
  assertEquals(row?.author_id, "local-author");
  assert(row?.recorded_at !== undefined);
});

Deno.test("mapTransaction : montant et mois conservés", () => {
  const row = mapTransaction(
    {
      id: "t-1",
      date: "2026-11-04",
      flux: "Entrée",
      categorie: "Écolage",
      montant: 50000,
      mois: "2026-11",
      updatedAt: "2026-11-04T10:00:00.000Z",
    },
    null,
  );
  assertEquals(row?.amount, 50000);
  assertEquals(row?.period_month, "2026-11");
});
