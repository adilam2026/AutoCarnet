# AutoCarnet — schéma cloud Supabase

## Comment appliquer la migration

1. Ouvre le dashboard Supabase de ton projet (`ugrypnavzzqsvuyxkphl`, "AutoCarnetV2" -
   le projet d'origine `gecqlxxhflnxlpderkyu` a été abandonné : son service
   d'authentification avait cessé de recharger ses réglages dashboard, même
   après redémarrage, aucune vraie donnée n'y avait encore été créée).
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

## Authentification : email + code à 6 chiffres, sans mot de passe

L'app n'a **aucun mot de passe** — création de compte et connexion sont la
même chose : l'utilisateur saisit son email (+ son nom la première fois),
reçoit un code à 6 chiffres, le saisit, et c'est tout. La sécurité "au
quotidien" sur chaque appareil vient du code d'accès local (PIN), pas d'un
mot de passe de compte.

Ça utilise l'endpoint OTP passwordless de Supabase (`signInWithOtp` +
`verifyOtp(type: 'email')`), dont le template d'email est **"Magic Link"**
(pas "Confirm signup", qui n'est plus utilisé du tout maintenant qu'il n'y a
plus de `signUp()` avec mot de passe). Par défaut ce template envoie un lien
cliquable et n'affiche pas le code — il faut l'éditer :

1. Dashboard → **Authentication** → **Email Templates**.
2. Ouvre **"Magic Link"** (dans la liste : "Send a one-time sign-in link or
   one-time password").
3. Remplace le bouton/lien par un texte qui affiche `{{ .Token }}` (le code
   à 6 chiffres). Exemple minimal :
   ```
   Votre code de vérification AutoCarnet : {{ .Token }}
   ```
4. Sauvegarde.

Sans cette étape, les emails partiront quand même mais l'utilisateur ne
verra aucun code à saisir dans l'app - juste un lien cassé (l'app n'utilise
jamais ce lien, elle attend uniquement le code).

## Ce qui n'est PAS encore fait

- **Stockage des pièces jointes** (photos, PDF de documents) : nécessite un
  bucket Supabase Storage + ses propres policies, pas encore créé.
- **Partage de véhicule entre utilisateurs** (mentionné au point 19 : "les
  véhicules partagés avec lui selon ses permissions") : le schéma actuel est
  mono-utilisateur strict (chaque ligne appartient à un seul `user_id`).
  Le partage nécessiterait une table `vehicle_members` (véhicule ↔
  utilisateurs ↔ niveau de permission) et des policies RLS plus complexes —
  volontairement pas construit tant que ce n'est pas confirmé comme
  nécessaire, pour ne pas complexifier la sécurité sans usage réel.
- **Le moteur de synchronisation** (file d'attente locale → cloud,
  déclenchement automatique, résolution de conflits, gestion des
  appareils/`devices`) : le compte email fonctionne (création et connexion
  par code à 6 chiffres, déconnexion simple/tous appareils), mais aucune
  donnée (véhicules, entretiens...) n'est encore synchronisée entre
  appareils. C'est la prochaine étape.
- **Test réel de bout en bout** : je n'ai ni téléphone ni boîte mail réelle
  pour recevoir un code de vérification depuis ce sandbox - je ne peux donc
  pas reproduire moi-même le scénario complet "créer un compte → recevoir le
  code → le saisir → être connecté". Le code compile et passe l'analyse
  statique, mais **toi seul peux valider ce parcours réellement** avant de
  le considérer fiable.

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
