-- ============================================================================
--  DTNH Assistant Club — date de naissance des joueurs
-- ============================================================================
--  Le club catégorise son effectif par tranche d'âge (U12, U14-U15, U16,
--  U17-U18). Sans date de naissance, la seule façon de savoir si un joueur est
--  dans la bonne catégorie était de refaire le calcul de tête à chaque
--  inscription.
--
--  On ajoute donc `birth_date` à `dtnh_players`, alimentée par le champ
--  `dateNaissance` (`yyyy-MM-dd`) de l'application. La colonne est
--  **nullable** : les fiches déjà synchronisées n'ont pas cette information et
--  restent valides ; l'application affiche simplement « âge inconnu ».
--
--  L'âge n'est pas stocké : il se déduit de la date, ce qui évite une donnée
--  qui devient fausse dès le lendemain de la synchronisation.
-- ============================================================================

alter table public.dtnh_players
  add column if not exists birth_date date;

comment on column public.dtnh_players.birth_date is
  'Date de naissance du joueur (nullable) ; l''âge est calculé à la lecture.';

-- Regroupement par âge : « quels joueurs fêtent leurs 12 ans cette saison ? ».
create index if not exists dtnh_players_birth_date_idx
  on public.dtnh_players (birth_date);
