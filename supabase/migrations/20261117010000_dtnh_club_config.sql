-- ============================================================================
--  DTNH Assistant Club — configuration du club (cible Google Sheets)
-- ============================================================================
--  Pourquoi cette table
--  --------------------
--  Jusqu'ici, l'URL `/exec` et le secret du webhook Apps Script vivaient dans
--  les *secrets de fonction* Supabase. C'est sûr, mais il fallait un accès au
--  dashboard et un redéploiement pour la moindre correction (l'URL `/exec`
--  change dès qu'on crée un nouveau déploiement Apps Script — cas très
--  fréquent en pratique, et source de « la synchronisation ne marche plus »).
--
--  Cette table rend la configuration **modifiable sans redéploiement** :
--
--      update public.dtnh_club_config
--         set sheets_webhook_url = 'https://script.google.com/macros/s/…/exec'
--       where id = 1;
--
--  L'Edge Function `dtnh-sync` lit cette ligne en priorité, puis retombe sur
--  les variables d'environnement (`DTNH_SHEETS_WEBHOOK_URL`, …) si elle est
--  absente : aucun déploiement existant ne casse.
--
--  Sécurité
--  --------
--  RLS activée **sans policy** : ni la clé anon ni la clé publishable ne
--  peuvent lire cette table. Seule la clé de service (utilisée par l'Edge
--  Function) y accède. Le secret n'est donc jamais exposé publiquement : il
--  n'est renvoyé qu'aux requêtes authentifiées (session Google ou secret
--  partagé), via l'action `config`.
-- ============================================================================

create table if not exists public.dtnh_club_config (
  -- Ligne unique : `id = 1` (contrainte explicite, pas de doublon possible).
  id integer primary key default 1,
  club_name text,
  -- URL `/exec` du déploiement Apps Script. Vide = club 100 % Supabase.
  sheets_webhook_url text,
  -- Secret partagé du webhook (`SHARED_SECRET` dans les propriétés du script).
  sheets_webhook_secret text,
  -- Identifiant du Google Sheet (informatif, affiché dans l'app).
  sheet_id text,
  -- Qui a mis à jour la ligne et quand : indispensable pour diagnostiquer.
  updated_at timestamptz not null default now(),
  updated_by text,
  constraint dtnh_club_config_singleton check (id = 1)
);

comment on table public.dtnh_club_config is
  'Configuration de synchronisation distribuée aux membres (ligne unique).';
comment on column public.dtnh_club_config.sheets_webhook_url is
  'URL /exec du webhook Apps Script ; vide = synchronisation Supabase seule.';
comment on column public.dtnh_club_config.sheets_webhook_secret is
  'Secret partagé du webhook ; renvoyé uniquement aux requêtes authentifiées.';

insert into public.dtnh_club_config (id)
values (1)
on conflict (id) do nothing;

alter table public.dtnh_club_config enable row level security;

-- Trace des modifications (audit minimal, sans dépendre d'un trigger lourd).
create or replace function public.dtnh_touch_club_config()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists dtnh_club_config_touch on public.dtnh_club_config;
create trigger dtnh_club_config_touch
  before update on public.dtnh_club_config
  for each row
  execute function public.dtnh_touch_club_config();
