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

## Configuration requise pour que la connexion par WhatsApp fonctionne

L'app propose maintenant **WhatsApp en premier** pour créer un compte ou se
connecter : l'utilisateur saisit son numéro (indicatif + numéro, jamais en
texte libre), reçoit un code à 6 chiffres par WhatsApp, le saisit — et c'est
tout, pas besoin d'adresse email. L'email reste disponible en solution de
repli ("Utiliser une adresse email à la place").

Ça vient directement de l'authentification téléphone de Supabase, mais
Supabase n'envoie jamais de SMS/WhatsApp lui-même — il faut brancher un
fournisseur externe. **C'est la seule étape que je ne peux pas faire moi-même**
(ça demande de créer un compte chez ce fournisseur, avec vérification
d'identité) :

1. Crée un compte sur [twilio.com](https://www.twilio.com) (offre d'essai
   gratuite avec crédit offert — suffisant pour tester ; au-delà, la
   facturation WhatsApp via Twilio est de l'ordre de quelques centimes par
   message, ce n'est pas totalement gratuit à grande échelle mais très bas
   coût, contrairement à l'email il n'y a pas de limite artificielle bloquante).
2. Dans Twilio, active le canal **WhatsApp** (Messaging → Try it out →
   Send a WhatsApp message, ou pour la production : WhatsApp Senders — ça
   demande une vérification Meta Business, qui prend quelques jours).
3. Récupère ton **Account SID** et ton **Auth Token** Twilio (jamais à me
   les donner en clair dans le chat — comme pour tout mot de passe/clé
   secrète : à saisir uniquement dans le dashboard Supabase, jamais ici).
4. Dashboard Supabase → **Authentication** → **Sign In / Providers** →
   ouvre le fournisseur **Phone** → active-le → choisis **Twilio** comme
   SMS provider → colle l'Account SID et l'Auth Token → dans le champ
   "Message Service SID / Sender", indique ton numéro WhatsApp Twilio.
5. Sauvegarde.

Sans cette étape, le bouton "Continuer avec WhatsApp" affichera une erreur
Supabase claire (pas un blocage silencieux) — le chemin email reste
utilisable en attendant.

## Configuration requise pour que la vérification par email fonctionne

L'app envoie un **code à 6 chiffres** (jamais un simple lien magique) pour
vérifier l'adresse email à la création de compte et pour "mot de passe
oublié" — plus simple et plus fiable qu'un lien profond (deep link) que je
ne peux pas tester moi-même sans appareil réel. Par défaut, Supabase envoie
un lien et n'affiche pas le code dans l'email. Il faut donc éditer 2
templates :

1. Dashboard → **Authentication** → **Email Templates**.
2. Ouvre **Confirm signup** : remplace le bouton/lien par un texte qui
   affiche `{{ .Token }}` (le code à 6 chiffres). Exemple minimal :
   ```
   Votre code de vérification AutoCarnet : {{ .Token }}
   ```
3. Fais la même chose sur **Reset Password** (utilisé pour "mot de passe
   oublié").
4. Sauvegarde chaque template.

Sans cette étape, les emails partiront quand même mais l'utilisateur ne
verra aucun code à saisir dans l'app.

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
  appareils/`devices`) : le compte email fonctionne (création, vérification,
  connexion, mot de passe oublié, déconnexion simple/tous appareils), mais
  aucune donnée (véhicules, entretiens...) n'est encore synchronisée entre
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
