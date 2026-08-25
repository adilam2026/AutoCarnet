/// Extensible list of operation categories (bloc 5, §8.2). 'Vidange' is the
/// engine oil change ("vidange moteur") - kept under its existing, already
///-stored label rather than renamed, so no vehicle's history or recurrence
/// rule silently stops matching (mission 2026, point 16: "aucune donnée
/// existante ne doit être perdue"). 'Vidange boîte de vitesses' (point 5)
/// is a fully separate entry next to it on purpose - never to be confused
/// with, or merged into, the engine's own vidange (point 7: two
/// independent échéance cycles, enforced by MaintenanceRepository's
/// per-category reminder reconciliation matching this exact string).
const List<String> maintenanceCategories = [
  'Vidange',
  'Vidange + filtres',
  'Vidange boîte de vitesses',
  'Révision',
  'Révision constructeur',
  'Filtre à huile',
  'Filtre à air',
  'Filtre habitacle',
  'Filtre carburant',
  'Plaquettes de frein',
  'Disques de frein',
  'Freinage',
  'Batterie',
  'Bougies',
  'Courroie de distribution',
  'Chaîne de distribution',
  'Courroie accessoires',
  'Embrayage',
  'Pneus',
  'Suspension',
  'Liquide de refroidissement',
  'Liquide de frein',
  'Climatisation',
  // AdBlue is deliberately NOT offered here (point 8's checklist names it,
  // but points 2-4 are more specific and take priority): it lives as its
  // own "Plein AdBlue" quick action backed by FuelEntries instead, so its
  // autonomie/échéance logic (AdblueRules, FuelRepository.
  // _reconcileAdblueReminder) stays in one place. Offering it again here
  // as a MaintenanceEntry would create a second, alert-less way to log the
  // same thing.
  'Contrôle / diagnostic',
  'Réparation moteur',
  'Réparation électrique',
  'Carrosserie',
  'Réparation',
  'Autre',
];
