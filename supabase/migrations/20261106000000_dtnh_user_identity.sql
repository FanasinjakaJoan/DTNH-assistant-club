-- ============================================================================
--  DTNH Assistant Club — identités & RLS par utilisateur
-- ============================================================================
--  Jusqu'ici toutes les tables étaient en RLS **sans aucune policy** : seule la
--  clé service_role (Edge Function) pouvait lire et écrire, et l'application
--  n'embarquait aucune clé Supabase.
--
--  Depuis la connexion Google, l'application présente le JWT du membre. Ce
--  fichier ouvre une lecture **authentifiée et en lecture seule** :
--    - un membre connecté voit les données du club (pointages, finances,
--      effectif) — c'est le besoin réel : tout le staff travaille sur les même
--      séances ;
--    - un visiteur non connecté (clé anon seule) ne voit **rien** ;
--    - l'écriture reste réservée à l'Edge Function (service_role), donc au
--      chemin de synchronisation validé, jamais à un client direct.
--
--  Traçabilité : `author_id` (pointages, finances) et `owner_id` (joueurs)
--  contiennent l'UUID Supabase du membre qui a saisi la ligne.
-- ============================================================================

-- ----------------------------------------------------------------------------
--  1. Colonnes d'identité
-- ----------------------------------------------------------------------------
alter table public.dtnh_players
  add column if not exists owner_id uuid;

alter table public.dtnh_sync_log
  add column if not exists user_id uuid;

comment on column public.dtnh_players.owner_id is
  'UUID Supabase du membre ayant créé la fiche joueur (null = import en masse).';
comment on column public.dtnh_sync_log.user_id is
  'UUID Supabase du membre auteur du lot (null = envoi par secret partagé).';

create index if not exists dtnh_attendance_author_idx
  on public.dtnh_attendance (author_id);
create index if not exists dtnh_transactions_author_idx
  on public.dtnh_transactions (author_id);
create index if not exists dtnh_players_owner_idx
  on public.dtnh_players (owner_id);
create index if not exists dtnh_sync_log_user_idx
  on public.dtnh_sync_log (user_id);

-- ----------------------------------------------------------------------------
--  2. Annuaire des membres du club
-- ----------------------------------------------------------------------------
--  `auth.users` n'est pas exposé via l'API REST. Cette vue (security_invoker)
--  permet à un membre connecté de voir qui d'autre fait partie du staff, sans
--  jamais exposer les autres colonnes d'authentification.
create or replace view public.dtnh_members
with (security_invoker = true) as
select
  id,
  email,
  coalesce(
    raw_user_meta_data ->> 'full_name',
    raw_user_meta_data ->> 'name',
    split_part(email, '@', 1)
  ) as display_name,
  raw_user_meta_data ->> 'avatar_url' as avatar_url,
  coalesce(raw_app_meta_data ->> 'provider', 'email') as provider,
  created_at as joined_at,
  last_sign_in_at
from auth.users;

comment on view public.dtnh_members is
  'Membres DTNH connectés (identité Google), lecture réservée aux membres authentifiés.';

-- ----------------------------------------------------------------------------
--  3. Policies
-- ----------------------------------------------------------------------------
--  Lecture pour tout rôle `authenticated`. La condition est explicite plutôt
--  que `using (true)` : elle documente l'intention et évite qu'un futur
--  `alter role anon` n'ouvre les tables par accident.

drop policy if exists dtnh_players_read on public.dtnh_players;
create policy dtnh_players_read on public.dtnh_players
  for select to authenticated
  using (auth.uid() is not null);

drop policy if exists dtnh_attendance_read on public.dtnh_attendance;
create policy dtnh_attendance_read on public.dtnh_attendance
  for select to authenticated
  using (auth.uid() is not null);

drop policy if exists dtnh_transactions_read on public.dtnh_transactions;
create policy dtnh_transactions_read on public.dtnh_transactions
  for select to authenticated
  using (auth.uid() is not null);

-- Le journal technique reste privé : même un membre connecté n'a pas à voir
-- les lots des autres appareils.
drop policy if exists dtnh_sync_log_read on public.dtnh_sync_log;
create policy dtnh_sync_log_read on public.dtnh_sync_log
  for select to authenticated
  using (user_id = auth.uid());

-- ----------------------------------------------------------------------------
--  4. Droits sur la vue des membres
-- ----------------------------------------------------------------------------
revoke all on public.dtnh_members from anon;
grant select on public.dtnh_members to authenticated;

-- ----------------------------------------------------------------------------
--  5. Garde-fou : écriture directe interdite aux clients
-- ----------------------------------------------------------------------------
--  Aucune policy INSERT/UPDATE/DELETE `to authenticated` n'est créée ici, et
--  c'est volontaire : les écritures passent par l'Edge Function, qui contrôle
--  le secret, l'identité et le journal. Ajouter une policy d'écriture ici
--  ouvrirait un chemin non journalisé.
