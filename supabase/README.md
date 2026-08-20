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

## Audit RLS (chantier session/multi-compte) — règle à respecter pour toute évolution future

Vérifié lors de l'audit multi-compte (voir aussi l'isolation côté app dans
`VehicleRepository`/`ProviderRepository`/`DocumentRepository`, méthode
`handleAccountSwitch`) : **le filtrage côté app (Drift/Flutter) n'est
jamais la seule barrière.** Chaque table de ce fichier a sa propre policy
RLS `auth.uid() = user_id`, appliquée par Postgres lui-même - un appel API
direct (en contournant complètement l'app mobile) avec le token d'un
compte B ne peut structurellement jamais lire une ligne appartenant au
compte A. Vérifié en direct (`curl` avec seulement la clé anonyme, sans
session) : les 15 tables renvoient `200 []`, jamais les données d'un
autre utilisateur.

Point d'attention pour la suite : seules `vehicles` (+ `vehicle_members`,
`vehicle_invite_codes` depuis 0004/0005) ont une policy étendue au
partage (`vehicle_members`). Toutes les autres tables listées ci-dessus
(`service_providers`, `documents`, `maintenance_entries`, `expenses`,
`fuel_entries`, `timeline_events`, `audit_events`, `reminders`,
`operation_frequency_preferences`, `mileage_entries`,
`document_versions`, `document_attachments`) restent strictement
`auth.uid() = user_id`, sans exception pour un collaborateur - ce qui est
sans risque aujourd'hui (aucune de ces tables n'est encore synchronisée,
seul `VehicleSyncService` existe), mais **le jour où l'une d'elles sera
synchronisée pour un véhicule partagé, sa policy select devra être
étendue avec la même jointure `vehicle_members` que `vehicles`** -
sinon un collaborateur autorisé sur le véhicule ne verra simplement rien
(échec silencieux, pas une fuite, mais à corriger). Ne jamais l'étendre
à l'aveugle sans revérifier l'absence de récursion (voir
`0005_fix_rls_recursion.sql`).

## Authentification : email + code à 6 chiffres, sans mot de passe

L'app n'a **aucun mot de passe** — création de compte et connexion sont la
même chose : l'utilisateur saisit son email (+ son nom la première fois),
reçoit un code à 6 chiffres, le saisit, et c'est tout. La sécurité "au
quotidien" sur chaque appareil vient du code d'accès local (PIN), pas d'un
mot de passe de compte.

Ça utilise l'endpoint OTP passwordless de Supabase (`signInWithOtp` +
`verifyOtp(type: 'email')`), dont l'email part sous le template **"Magic
Link"** pour un compte déjà existant, et **"Confirm signup"** pour une
toute première adresse. Par défaut, ces deux templates envoient un lien
cliquable (`{{ .ConfirmationURL }}`) et n'affichent aucun code — il faut
les éditer, et c'est plus qu'une question d'affichage :

**Important - retirer complètement le lien, pas seulement le montrer en
moins gros.** Si le template garde `{{ .ConfirmationURL }}` n'importe où
(même dans un texte de secours du genre "si le bouton ne marche pas,
clique sur ce lien"), les scanners de sécurité de la messagerie (Gmail
notamment) peuvent "cliquer" ce lien automatiquement dès l'arrivée du
mail, pour vérifier qu'il n'est pas malveillant - avant même que
l'utilisateur ouvre l'email. Or le lien et le code à 6 chiffres
consomment le **même** jeton à usage unique côté Supabase : si le
scanner l'utilise en premier, le code affiché à l'utilisateur est déjà
invalidé, et `verifyOtp` répond "Token has expired or is invalid" même
quelques secondes après l'envoi - Supabase documente ce comportement
explicitement dans son guide de dépannage. La seule protection fiable
est de ne jamais inclure `{{ .ConfirmationURL }}` dans le template.

1. Dashboard → **Authentication** → **Email Templates**.
2. Ouvre **"Magic Link"** (dans la liste : "Send a one-time sign-in link or
   one-time password"). Remplace tout le corps du template - pas juste le
   bouton - par quelque chose comme :
   ```html
   <h2>Code de vérification AutoCarnet</h2>
   <p>Votre code de vérification est :</p>
   <h1>{{ .Token }}</h1>
   <p>Ce code expire dans 1 heure. Si vous n'êtes pas à l'origine de cette
   demande, ignorez cet email.</p>
   ```
   Aucun bouton, aucun `<a href="...">`, aucune mention de
   `{{ .ConfirmationURL }}` nulle part dans le HTML.
3. Change aussi le **Subject** (actuellement "Your sign-in link", trompeur
   pour un flux à code) : `Votre code de vérification AutoCarnet`.
4. Répète exactement la même chose sur **"Confirm signup"** (utilisé pour
   la toute première adresse email d'un nouveau compte) : même corps, même
   consigne "aucun lien", même changement de Subject.
5. Sauvegarde les deux templates.

Sans cette étape, les emails partiront quand même mais soit l'utilisateur
ne verra aucun code (juste un lien), soit - le cas ici - il verra un code
déjà invalidé par un scanner automatique avant même de le lire.

## Synchronisation cloud (véhicules) — appliquer la migration 0003

Étape supplémentaire pour activer le temps quasi-réel (nécessaire uniquement
si tu veux que deux appareils/comptes voient les mêmes véhicules se
synchroniser automatiquement, pas seulement au prochain lancement de l'app) :

1. SQL Editor → **New query**.
2. Colle le contenu de `migrations/0003_enable_realtime.sql`.
3. **Run**.

Sans cette étape, la synchronisation continue de fonctionner (push au
démarrage + toutes les 2 minutes), mais les changements d'un autre appareil
n'apparaissent qu'au prochain passage périodique au lieu d'en quelques
secondes.

## Partage de véhicule — appliquer la migration 0004

Étape nécessaire pour que "Partager le véhicule" / "Rejoindre un véhicule"
fonctionnent :

1. SQL Editor → **New query**.
2. Colle le contenu de `migrations/0004_vehicle_sharing.sql`.
3. **Run**.

Ça crée `vehicle_members` (qui a accès à quel véhicule, et à quel niveau)
et `vehicle_invite_codes` (les codes d'invitation à 8 caractères,
`Q7K9-M2P4` à l'affichage), plus deux fonctions
`preview_vehicle_invite`/`accept_vehicle_invite` qui sont les seules portes
d'entrée pour rejoindre un véhicule avec un code. Étend aussi les policies
RLS de `vehicles` (un "éditeur" peut lire/écrire, un "lecteur" peut
seulement lire) et ajoute un trigger qui refuse la suppression du véhicule
à quiconque n'est pas son propriétaire, même si un éditeur essaie de le
faire directement en base (jamais seulement côté app).

Sans cette étape, l'app affiche les écrans de partage mais chaque appel
échouera (tables/fonctions inexistantes) - échec silencieux, sans jamais
bloquer l'usage normal (non partagé) du véhicule.

## Correctif obligatoire — migration 0005 (récursion RLS)

0004 telle qu'écrite au départ provoquait une "infinite recursion detected
in policy" (Postgres 42P17) : la policy de `vehicles` regarde dans
`vehicle_members`, et celle de `vehicle_members` regardait dans `vehicles`
en retour - repéré en testant en conditions réelles juste après 0004.
**Obligatoire si tu as appliqué 0004 avant que ce correctif existe** :

1. SQL Editor → **New query**.
2. Colle le contenu de `migrations/0005_fix_rls_recursion.sql`.
3. **Run**.

## Ce qui n'est PAS encore fait

- **Stockage des pièces jointes** (photos, PDF de documents) : nécessite un
  bucket Supabase Storage + ses propres policies, pas encore créé.
- **Synchronisation au-delà de la fiche véhicule** : seule la table
  `vehicles` est aujourd'hui synchronisée (push automatique à chaque
  modification locale + pull périodique/temps réel via Supabase Realtime,
  résolution de conflit "dernier écrit gagne" sur `updated_at`). Entretiens,
  documents, dépenses, etc. restent pour l'instant strictement locaux à
  chaque appareil, même sur un véhicule partagé - un collaborateur "peut
  modifier" verra donc bien le kilométrage/la fiche se synchroniser avec le
  propriétaire, mais pas (encore) les entretiens/documents qu'il ajoute. À
  étendre au même moteur de synchronisation dans une prochaine étape.
- **Résolution de conflit avec choix utilisateur** (point 23 du cahier des
  charges) : le moteur actuel résout un conflit sur `vehicles` par "dernier
  écrit gagne" (`updated_at` le plus récent l'emporte) - fiable pour une
  utilisation normale, mais si le propriétaire et un éditeur modifient le
  même champ (ex. kilométrage) quasi simultanément hors ligne tous les
  deux, la version la plus ancienne est silencieusement perdue au lieu
  d'afficher les deux valeurs pour arbitrage. Pas encore construit.
- **Notifications de collaboration** (invitation acceptée, accès retiré) :
  pas encore construites - aujourd'hui le propriétaire doit ouvrir "Partage
  et accès" pour voir qui a rejoint.
- **Test réel de bout en bout à deux comptes** : je n'ai ni deuxième
  téléphone ni boîte mail réelle pour recevoir un code de vérification
  depuis ce sandbox - je ne peux donc pas créer moi-même deux sessions
  authentifiées et reproduire le parcours complet "compte A génère un code
  → compte B le saisit → les deux voient le même véhicule se
  synchroniser". Le code compile, passe l'analyse statique et les tests
  unitaires (mapping, permissions, génération/normalisation de code), mais
  **ce parcours à deux comptes doit être validé par toi** avant d'être
  considéré fiable - voir la checklist de test dans le message qui
  accompagne cette livraison.

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
