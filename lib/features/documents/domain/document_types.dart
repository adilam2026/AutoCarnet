/// Extensible list of document types (bloc 4, §7.2). New types can be
/// appended without touching the schema or the repository.
const List<String> vehicleDocumentTypes = [
  'Carte grise',
  'Assurance',
  'Visite technique',
  'Vignette',
  'Certificat de conformité',
  'Facture d\'achat',
  'Facture de vente',
  'Contrat de financement',
  'Contrat de leasing',
  'Garantie constructeur',
  'Garantie extension',
  'Manuel utilisateur',
  'Carnet d\'entretien',
  'Autre',
];

const List<String> driverDocumentTypes = [
  'Permis de conduire',
  'Pièce d\'identité',
  'Autre',
];
