import '../../../core/database/database.dart';

/// Result of estimating when the next revision will actually happen -
/// distinguishes what's known for certain (mileage/date thresholds, always
/// computable from the last revision + a frequency) from what's only ever a
/// guess (a calendar date derived from the owner's recent driving pace,
/// which requires enough mileage history to be meaningful).
class RevisionEstimate {
  final double? nextMileage;
  final DateTime? nextDateByFrequency;
  final double? remainingKm;
  final DateTime? estimatedDateByPace;

  /// The single most useful "probable" date to show the owner: the earlier
  /// of the pace-based estimate and the frequency's calendar deadline when
  /// both exist (RG: "10 000 km OU 12 mois, au premier terme atteint"),
  /// otherwise whichever of the two is available.
  final DateTime? probableDate;
  final bool isOverdueByMileage;
  final bool isOverdueByDate;

  const RevisionEstimate({
    this.nextMileage,
    this.nextDateByFrequency,
    this.remainingKm,
    this.estimatedDateByPace,
    this.probableDate,
    this.isOverdueByMileage = false,
    this.isOverdueByDate = false,
  });

  bool get isOverdue => isOverdueByMileage || isOverdueByDate;
  bool get hasAnyEstimate => nextMileage != null || nextDateByFrequency != null;
}

/// Average km driven per month, computed only from real mileage-history
/// entries and biased toward recent data (RG: "utiliser en priorité les
/// données récentes"). Returns null rather than a misleading number when
/// there isn't enough spread to be meaningful - never invent a pace from a
/// single reading or from readings taken the same day.
double? estimateMonthlyPaceKm(
  List<MileageEntry> history, {
  int windowMonths = 6,
  int minDaysSpread = 14,
}) {
  if (history.length < 2) return null;
  final sorted = [...history]..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
  final cutoff = DateTime.now().subtract(Duration(days: windowMonths * 30));
  var windowed = sorted.where((e) => e.recordedAt.isAfter(cutoff)).toList();
  if (windowed.length < 2) windowed = sorted;

  final first = windowed.first;
  final last = windowed.last;
  final days = last.recordedAt.difference(first.recordedAt).inDays;
  if (days < minDaysSpread) return null;
  final deltaKm = last.value - first.value;
  if (deltaKm <= 0) return null;
  return deltaKm / (days / 30.4);
}

/// Estimates the next revision from the last one, a km and/or month
/// frequency, and (optionally) the owner's recent driving pace. Never
/// fabricates a calendar date without [monthlyPaceKm] - without it, only
/// the mileage-based threshold (always exact, no guessing involved) is
/// returned.
RevisionEstimate estimateNextRevision({
  double? lastRevisionMileage,
  DateTime? lastRevisionDate,
  double? frequencyKm,
  int? frequencyMonths,
  required double currentMileage,
  double? monthlyPaceKm,
}) {
  final nextMileage = (lastRevisionMileage != null && frequencyKm != null)
      ? lastRevisionMileage + frequencyKm
      : null;
  final nextDateByFrequency =
      (lastRevisionDate != null && frequencyMonths != null)
          ? DateTime(lastRevisionDate.year,
              lastRevisionDate.month + frequencyMonths, lastRevisionDate.day)
          : null;
  return _buildEstimate(
    nextMileage: nextMileage,
    nextDateThreshold: nextDateByFrequency,
    currentMileage: currentMileage,
    monthlyPaceKm: monthlyPaceKm,
  );
}

/// Same estimate, but for a next-due threshold that's already known
/// directly (e.g. from an operation's own nextDueMileage/nextDueDate,
/// already fed into the reminders engine) rather than derived from a
/// "last revision + frequency" pair.
RevisionEstimate estimateFromKnownNextDue({
  double? nextMileage,
  DateTime? nextDateThreshold,
  required double currentMileage,
  double? monthlyPaceKm,
}) {
  return _buildEstimate(
    nextMileage: nextMileage,
    nextDateThreshold: nextDateThreshold,
    currentMileage: currentMileage,
    monthlyPaceKm: monthlyPaceKm,
  );
}

RevisionEstimate _buildEstimate({
  double? nextMileage,
  DateTime? nextDateThreshold,
  required double currentMileage,
  double? monthlyPaceKm,
}) {
  final now = DateTime.now();
  final remainingKm = nextMileage != null ? nextMileage - currentMileage : null;

  DateTime? estimatedDateByPace;
  if (remainingKm != null &&
      remainingKm > 0 &&
      monthlyPaceKm != null &&
      monthlyPaceKm > 0) {
    final monthsRemaining = remainingKm / monthlyPaceKm;
    estimatedDateByPace = now.add(Duration(days: (monthsRemaining * 30.4).round()));
  }

  DateTime? probableDate;
  if (estimatedDateByPace != null && nextDateThreshold != null) {
    probableDate = estimatedDateByPace.isBefore(nextDateThreshold)
        ? estimatedDateByPace
        : nextDateThreshold;
  } else {
    probableDate = estimatedDateByPace ?? nextDateThreshold;
  }

  return RevisionEstimate(
    nextMileage: nextMileage,
    nextDateByFrequency: nextDateThreshold,
    remainingKm: remainingKm,
    estimatedDateByPace: estimatedDateByPace,
    probableDate: probableDate,
    isOverdueByMileage: remainingKm != null && remainingKm <= 0,
    isOverdueByDate: nextDateThreshold != null && nextDateThreshold.isBefore(now),
  );
}

/// Observes the interval between past revisions (chronological mileages) so
/// the UI can *suggest* a frequency - it never overrides a configured one on
/// its own, the owner always has to confirm (RG: "ne jamais modifier
/// automatiquement une fréquence configurée sans son accord"). Needs at
/// least two gaps (three revisions) to be meaningful.
double? observeFrequencyKm(List<double> chronologicalRevisionMileages) {
  if (chronologicalRevisionMileages.length < 3) return null;
  final gaps = <double>[];
  for (var i = 1; i < chronologicalRevisionMileages.length; i++) {
    final gap = chronologicalRevisionMileages[i] - chronologicalRevisionMileages[i - 1];
    if (gap > 0) gaps.add(gap);
  }
  if (gaps.length < 2) return null;
  return gaps.reduce((a, b) => a + b) / gaps.length;
}
