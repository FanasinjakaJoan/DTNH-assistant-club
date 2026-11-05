/// Sens du flux financier.
enum TransactionFlow {
  income(code: 'IN', label: 'Entrée', sign: 1),
  expense(code: 'OUT', label: 'Sortie', sign: -1);

  const TransactionFlow({
    required this.code,
    required this.label,
    required this.sign,
  });

  final String code;
  final String label;
  final int sign;

  static TransactionFlow fromCode(String? code) {
    if (code == null) return TransactionFlow.expense;
    final normalized = code.trim().toUpperCase();
    return normalized == 'IN' || normalized == 'ENTREE' || normalized == 'ENTRÉE'
        ? TransactionFlow.income
        : TransactionFlow.expense;
  }
}

/// Motif (catégorie) d'une transaction.
///
/// Chaque motif est rattaché à un [flow] et déclare les **champs spécifiques**
/// que le formulaire dédié doit afficher. C'est ce qui permet d'avoir un
/// formulaire d'écolage (joueur + mois) et un formulaire de rafraîchissement
/// (événement) sans dupliquer la logique de validation.
enum TransactionCategory {
  ecolage(
    code: 'ECOLAGE',
    label: 'Écolage',
    flow: TransactionFlow.income,
    description: 'Frais de scolarité mensuels',
    requiresPlayer: true,
    requiresPeriod: true,
  ),
  cotisation(
    code: 'COTISATION',
    label: 'Cotisation exceptionnelle',
    flow: TransactionFlow.income,
    description: 'Tournoi, déplacement, tenue',
  ),
  billetterie(
    code: 'BILLETTERIE',
    label: 'Vente de billets',
    flow: TransactionFlow.income,
    description: 'Billets de match / événement',
    requiresEvent: true,
  ),
  autreEntree(
    code: 'AUTRE_ENTREE',
    label: 'Autre entrée',
    flow: TransactionFlow.income,
    description: 'Don, sponsoring, divers',
  ),
  locationTerrain(
    code: 'LOCATION_TERRAIN',
    label: 'Location de terrain',
    flow: TransactionFlow.expense,
    description: 'Salle ou terrain de jeu',
  ),
  salaireCoach(
    code: 'SALAIRE_COACH',
    label: 'Salaire / indemnité coach',
    flow: TransactionFlow.expense,
    description: 'Rémunération de l\'encadrement',
    requiresStaff: true,
    requiresPeriod: true,
  ),
  rafraichissement(
    code: 'RAFRAICHISSEMENT',
    label: 'Rafraîchissements',
    flow: TransactionFlow.expense,
    description: 'Eau, boissons, collations',
    requiresEvent: true,
  ),
  autreSortie(
    code: 'AUTRE_SORTIE',
    label: 'Autre sortie',
    flow: TransactionFlow.expense,
    description: 'Matériel, transport, divers',
  );

  const TransactionCategory({
    required this.code,
    required this.label,
    required this.flow,
    required this.description,
    this.requiresPlayer = false,
    this.requiresPeriod = false,
    this.requiresStaff = false,
    this.requiresEvent = false,
  });

  final String code;
  final String label;
  final TransactionFlow flow;
  final String description;

  /// Champ « Joueur concerné » (écolage, cotisation nominative).
  final bool requiresPlayer;

  /// Champ « Mois concerné » (`yyyy-MM`).
  final bool requiresPeriod;

  /// Champ « Coach / membre du staff ».
  final bool requiresStaff;

  /// Champ « Événement » (match, entraînement, tournoi).
  final bool requiresEvent;

  static List<TransactionCategory> byFlow(TransactionFlow flow) =>
      TransactionCategory.values.where((c) => c.flow == flow).toList();

  static TransactionCategory? tryParse(String? code) {
    if (code == null) return null;
    final normalized = code.trim().toUpperCase().replaceAll(' ', '_');
    for (final category in TransactionCategory.values) {
      if (category.code == normalized || category.name.toUpperCase() == normalized) {
        return category;
      }
    }
    return null;
  }

  static TransactionCategory fromCode(String? code) =>
      tryParse(code) ?? TransactionCategory.autreEntree;
}

/// Moyens de paiement réellement utilisés au club (mobile money inclus).
enum PaymentMethod {
  cash(code: 'CASH', label: 'Espèces'),
  mvola(code: 'MVOLA', label: 'MVola'),
  orangeMoney(code: 'ORANGE_MONEY', label: 'Orange Money'),
  airtelMoney(code: 'AIRTEL_MONEY', label: 'Airtel Money'),
  bankTransfer(code: 'BANK_TRANSFER', label: 'Virement bancaire'),
  cheque(code: 'CHEQUE', label: 'Chèque'),
  other(code: 'OTHER', label: 'Autre');

  const PaymentMethod({required this.code, required this.label});

  final String code;
  final String label;

  static PaymentMethod? tryParseOrNull(String? code) {
    if (code == null) return null;
    final normalized = code.trim().toUpperCase().replaceAll(' ', '_');
    for (final method in PaymentMethod.values) {
      if (method.code == normalized) return method;
    }
    return null;
  }

  static PaymentMethod fromCode(String? code) =>
      tryParseOrNull(code) ?? PaymentMethod.cash;
}
