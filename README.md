# AutoCarnet

Compagnon numérique pour la gestion de véhicules (Flutter, Android + iOS,
base de code unique).

## Stack

- Flutter / Dart, Riverpod (state management), go_router (navigation)
- Drift (SQLite) pour une base locale offline-first
- Architecture feature-first : `lib/features/<module>/{data,domain,presentation}`

## Démarrer

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs # régénère core/database/database.g.dart
flutter run
```

## Tests

```bash
flutter analyze
flutter test
```

## Périmètre actuel

Implémenté : véhicules (création rapide, fiche, kilométrage avec règles de
cohérence), tableau de bord, documents (types, expiration, renouvellement en
versions), entretiens (pièces, main-d'œuvre, dépense liée), dépenses,
carburant (calcul de consommation entre pleins complets), prestataires
(référentiel réutilisable), timeline auto-alimentée, rappels calculés,
verrouillage PIN/biométrique local.

Prévu pour une phase suivante (le modèle de données les anticipe déjà) :
pneus, sinistres, partage/collaboration, moteur de rapports/export, backend
et synchronisation cloud, recherche globale, corbeille/audit complets.
