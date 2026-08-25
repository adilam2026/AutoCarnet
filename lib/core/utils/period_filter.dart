import 'package:flutter/material.dart';
import '../../core/widgets/date_field.dart';

enum PeriodKind { all, thisMonth, last3Months, thisYear, lastYear, custom }

/// Shared period filter used by every history/list screen (historique,
/// dépenses, carburant...) so "3 derniers mois" or "Année en cours" always
/// mean the same thing everywhere.
class PeriodFilter {
  final PeriodKind kind;
  final DateTimeRange? customRange;
  const PeriodFilter._(this.kind, [this.customRange]);

  static const all = PeriodFilter._(PeriodKind.all);
  static const thisMonth = PeriodFilter._(PeriodKind.thisMonth);
  static const last3Months = PeriodFilter._(PeriodKind.last3Months);
  static const thisYear = PeriodFilter._(PeriodKind.thisYear);
  static const lastYear = PeriodFilter._(PeriodKind.lastYear);
  factory PeriodFilter.custom(DateTimeRange range) =>
      PeriodFilter._(PeriodKind.custom, range);

  static const presets = [all, thisMonth, last3Months, thisYear, lastYear];

  String get label => switch (kind) {
        PeriodKind.all => 'Tout',
        PeriodKind.thisMonth => 'Mois en cours',
        PeriodKind.last3Months => '3 derniers mois',
        PeriodKind.thisYear => 'Année en cours',
        PeriodKind.lastYear => 'Année précédente',
        PeriodKind.custom => customRange == null
            ? 'Période...'
            : '${_fmt(customRange!.start)} - ${_fmt(customRange!.end)}',
      };

  bool matches(DateTime date) {
    final now = DateTime.now();
    switch (kind) {
      case PeriodKind.all:
        return true;
      case PeriodKind.thisMonth:
        return date.year == now.year && date.month == now.month;
      case PeriodKind.last3Months:
        return date.isAfter(now.subtract(const Duration(days: 90)));
      case PeriodKind.thisYear:
        return date.year == now.year;
      case PeriodKind.lastYear:
        return date.year == now.year - 1;
      case PeriodKind.custom:
        final range = customRange;
        if (range == null) return true;
        final day = DateTime(date.year, date.month, date.day);
        return !day.isBefore(range.start) &&
            !day.isAfter(range.end.add(const Duration(days: 1)));
    }
  }

  static String _fmt(DateTime d) => formatDdMmYyyy(d);

  @override
  bool operator ==(Object other) =>
      other is PeriodFilter &&
      other.kind == kind &&
      other.customRange?.start == customRange?.start &&
      other.customRange?.end == customRange?.end;

  @override
  int get hashCode => Object.hash(kind, customRange?.start, customRange?.end);
}

/// Compact horizontal chip row for period selection - never a form.
class PeriodFilterChips extends StatelessWidget {
  const PeriodFilterChips({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final PeriodFilter value;
  final ValueChanged<PeriodFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final preset in PeriodFilter.presets) ...[
            ChoiceChip(
              label: Text(preset.label),
              selected: value.kind == preset.kind,
              onSelected: (_) => onChanged(preset),
            ),
            const SizedBox(width: 8),
          ],
          ChoiceChip(
            label: Text(value.kind == PeriodKind.custom
                ? value.label
                : 'Période...'),
            selected: value.kind == PeriodKind.custom,
            onSelected: (_) async {
              final now = DateTime.now();
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(1990),
                lastDate: DateTime(now.year + 1),
                initialDateRange: value.customRange,
              );
              if (picked != null) onChanged(PeriodFilter.custom(picked));
            },
          ),
        ],
      ),
    );
  }
}
