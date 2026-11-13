-- ============================================================================
--  DTNH Assistant Club — schéma de synchronisation Supabase
-- ============================================================================
--  Créé sur le projet `osjsczvsnyknkdwbciab` (région us-east-1).
--  Historique côté Supabase : migration `dtnh_sync_schema`.
--
--  Principe : l'application Flutter reste **offline-first** (Hive local) et
--  pousse ses lots vers l'Edge Function `dtnh-sync`, qui écrit ici en upsert
--  idempotent (la clé primaire est l'UUID généré par le téléphone).
--
--  Sécurité : la RLS est activée **sans aucune policy**. La clé anon ne peut
--  donc ni lire ni écrire. Seule la clé service_role (utilisée par l'Edge
--  Function) a accès. L'application, elle, n'embarque aucune clé Supabase :
--  elle présente un simple secret partagé à la fonction.
-- ============================================================================

create table if not exists public.dtnh_players (
  id text primary key,
  full_name text not null,
  category text not null,
  jersey_number integer,
  phone text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.dtnh_attendance (
  id text primary key,
  session_id text not null,
  session_date date not null,
  recorded_at timestamptz not null,
  category text not null,
  player_id text not null,
  player_name text not null,
  jersey_number integer,
  status text not null,
  author_id text not null,
  author_name text not null,
  note text,
  updated_at timestamptz not null,
  synced_at timestamptz not null default now()
);

create table if not exists public.dtnh_transactions (
  id text primary key,
  date date not null,
  flow text not null,
  category text not null,
  amount bigint not null,
  payment_method text not null,
  details text,
  player_name text,
  staff_name text,
  event_name text,
  period_month text,
  author_id text not null,
  author_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null,
  synced_at timestamptz not null default now()
);

-- Journal des lots reçus : sert au diagnostic (« mon téléphone a-t-il envoyé ? »).
create table if not exists public.dtnh_sync_log (
  id bigserial primary key,
  batch_id text,
  device_id text,
  action text not null,
  item_count integer not null default 0,
  received_at timestamptz not null default now()
);

create index if not exists dtnh_attendance_session_date_idx
  on public.dtnh_attendance (session_date desc);
create index if not exists dtnh_attendance_player_idx
  on public.dtnh_attendance (player_id);
create index if not exists dtnh_attendance_category_idx
  on public.dtnh_attendance (category);
create index if not exists dtnh_transactions_date_idx
  on public.dtnh_transactions (date desc);
create index if not exists dtnh_transactions_month_idx
  on public.dtnh_transactions (period_month);
create index if not exists dtnh_players_category_idx
  on public.dtnh_players (category);
create index if not exists dtnh_sync_log_received_idx
  on public.dtnh_sync_log (received_at desc);

alter table public.dtnh_players enable row level security;
alter table public.dtnh_attendance enable row level security;
alter table public.dtnh_transactions enable row level security;
alter table public.dtnh_sync_log enable row level security;

comment on table public.dtnh_players is
  'Roster DTNH synchronisé depuis l''application (Edge Function dtnh-sync).';
comment on table public.dtnh_attendance is
  'Pointages DTNH : une ligne par joueur et par séance.';
comment on table public.dtnh_transactions is
  'Mouvements financiers DTNH (montants en Ariary entiers).';

-- ----------------------------------------------------------------------------
--  Vues d'agrégation : lecture immédiate depuis le SQL Editor / Grafana.
-- ----------------------------------------------------------------------------
create or replace view public.dtnh_finance_summary as
select
  to_char(date, 'YYYY-MM') as mois,
  sum(case when flow = 'IN' then amount else 0 end) as entrees_ar,
  sum(case when flow = 'OUT' then amount else 0 end) as sorties_ar,
  sum(case when flow = 'IN' then amount else -amount end) as solde_ar,
  count(*) as operations
from public.dtnh_transactions
group by 1
order by 1 desc;

create or replace view public.dtnh_attendance_summary as
select
  session_date as seance,
  category as categorie,
  count(*) as pointes,
  count(*) filter (where status in ('PRESENT', 'LATE')) as presents,
  count(*) filter (where status = 'ABSENT') as absents,
  count(*) filter (where status = 'EXCUSED') as excuses
from public.dtnh_attendance
group by 1, 2
order by 1 desc, 2;
