/// Overall state of a customer's verification application.
enum VerificationStatus {
  notStarted,
  draft,
  pending,
  underReview,
  approved,
  rejected,
}

/// Dwelling type captured during the credit application.
enum HouseType { independent, apartment, shared }

/// Whether the customer owns or rents their residence.
enum Ownership { owned, rented, family }

extension VerificationStatusX on VerificationStatus {
  bool get isTerminal =>
      this == VerificationStatus.approved || this == VerificationStatus.rejected;
  bool get isSubmitted =>
      this == VerificationStatus.pending ||
      this == VerificationStatus.underReview ||
      isTerminal;
}
