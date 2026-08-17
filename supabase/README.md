# AutoCarnet — schéma cloud Supabase

## Comment appliquer la migration

1. Ouvre le dashboard Supabase de ton projet (`gecqlxxhflnxlpderkyu`).
2. Menu de gauche → **SQL Editor** → **New query**.
3. Colle tout le contenu de `migrations/0001_init.sql`.
4. Clique **Run**.

Ça crée : `profiles`, `devices`, `vehicles`, `mileage_entries`,
`service_providers`, `documents` + `document_versions` +
`document_attachments`, `maintenance_entries` + `maintenance_parts`,
`expenses`, `fuel_entries`, `timeline_events`, `audit_events`,
`operation_frequency_preferences`, `reminders` — le miroir exact du schéma
local (Drift/SQLite), avec Row Level Security activé partout : chaque
utilisateur ne peut lire/écrire que ses propres lignes, contrôlé par
Postgres lui-même (pas seulement par l'app Flutter).

## Vérifier que ça a marché

Dans le SQL Editor :

```sql
select tablename, rowsecurity from pg_tables where schemaname = 'public';
select tablename, policyname from pg_policies where schemaname = 'public' order by 1;
```

Chaque table doit apparaître avec `rowsecurity = true` et 4 policies
(select/insert/update/delete).

## Ce qui n'est PAS encore dans cette migration

- **Stockage des pièces jointes** (photos, PDF de documents) : nécessite un
  bucket Supabase Storage + ses propres policies, pas encore créé.
- **Partage de véhicule entre utilisateurs** (mentionné au point 19 : "les
  véhicules partagés avec lui selon ses permissions") : le schéma actuel est
  mono-utilisateur strict (chaque ligne appartient à un seul `user_id`).
  Le partage nécessiterait une table `vehicle_members` (véhicule ↔
  utilisateurs ↔ niveau de permission) et des policies RLS plus complexes —
  volontairement pas construit tant que ce n'est pas confirmé comme
  nécessaire, pour ne pas complexifier la sécurité sans usage réel.
- **Le moteur de synchronisation lui-même** (file d'attente locale → cloud,
  déclenchement automatique, résolution de conflits) : c'est le code Flutter
  qui vient après ce schéma, pas encore écrit.
- **L'authentification email** (écrans de création de compte, vérification,
  mot de passe oublié) côté app : vient aussi après.

## Notes de conception

- Les identifiants (`id`) sont des `uuid` — exactement les mêmes valeurs que
  celles générées localement par l'app (`uuid v4`), donc une ligne créée
  hors connexion garde le même id une fois synchronisée : pas de
  remappage d'id nécessaire dans le moteur de synchronisation.
- `user_id` a `default auth.uid()` : l'app n'a jamais besoin de le fournir
  explicitement à l'insertion, Supabase le déduit du token de la session
  connectée. Les policies RLS vérifient quand même explicitement
  `user_id = auth.uid()` sur chaque opération, y compris à l'insertion — un
  client qui tenterait d'écrire avec un `user_id` différent du sien serait
  rejeté par la base, pas seulement par l'app.
