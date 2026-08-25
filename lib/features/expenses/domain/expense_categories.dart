/// Extensible list of expense categories (bloc 6, §9.3).
const List<String> expenseCategories = [
  'Entretien',
  'Réparation',
  'Assurance',
  'Carte grise',
  'Vignette',
  'Visite technique',
  'Carburant',
  // Distinct from 'Carburant' on purpose (mission 2026, point 12): AdBlue
  // must stay identifiable as its own expense line, never blended into
  // classic fuel spend.
  'AdBlue',
  'Péage',
  'Lavage',
  'Parking',
  'Accessoires',
  'Pneus',
  'Financement',
  'Leasing',
  'Amendes',
  'Divers',
];
