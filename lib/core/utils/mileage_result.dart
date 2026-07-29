/// Outcome of a mileage coherence check (RG-VEH-005, Principe 7: no silent
/// inconsistency - explain, propose, and only block when truly necessary).
sealed class MileageCheckResult {
  const MileageCheckResult();
}

/// The new value is coherent with existing history, nothing to confirm.
class MileageOk extends MileageCheckResult {
  const MileageOk();
}

/// The new value is lower than the current one but does not conflict with
/// any recorded operation - the user may confirm and proceed (Situation A).
class MileageNeedsConfirmation extends MileageCheckResult {
  final double currentMileage;
  final double newMileage;
  const MileageNeedsConfirmation({
    required this.currentMileage,
    required this.newMileage,
  });
}

/// The new value would make recorded operations inconsistent - the save is
/// blocked until the user fixes the conflicting entries (Situation B).
class MileageBlocked extends MileageCheckResult {
  final List<String> conflictingDescriptions;
  const MileageBlocked(this.conflictingDescriptions);
}
