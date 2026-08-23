import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_format.dart';
import '../../../core/utils/feedback.dart';
import '../../../core/utils/layout.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../../../core/widgets/section_header.dart';
import '../../documents/data/document_repository.dart';
import '../../maintenance/data/maintenance_repository.dart';
import '../../onboarding_lock/data/local_profile_repository.dart';
import '../../reminders/data/reminder_repository.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../../vehicles/domain/vehicle_health.dart';
import '../../vehicles/presentation/providers/vehicle_form_providers.dart';
import '../domain/resale_pdf.dart';
import '../domain/resale_readiness.dart';
import '../domain/resale_recommendations.dart';
import '../domain/valuation/valuation_engine.dart';
import '../domain/valuation/valuation_models.dart';
import 'widgets/valuation_breakdown_sheet.dart';

/// Resale hub (bloc 18): resale-estimate framework, a health score derived
/// from the carnet's own data, a preparation checklist, and a PDF dossier
/// generator - everything built from data already collected elsewhere
/// (Principe 2), nothing fabricated.
class ResaleBody extends ConsumerStatefulWidget {
  const ResaleBody({super.key});

  @override
  ConsumerState<ResaleBody> createState() => _ResaleBodyState();
}

class _ResaleBodyState extends ConsumerState<ResaleBody> {
  String? _selectedVehicleId;

  @override
  Widget build(BuildContext context) {
    final vehiclesAsync = ref.watch(vehiclesListProvider);

    return vehiclesAsync.when(
      loading: () => const LoadingView(),
      error: (e, _) =>
          const ErrorView(message: 'Impossible de charger ces données. Réessayez dans un instant.'),
      data: (vehicles) {
        if (vehicles.isEmpty) {
          return const EmptyState(
            icon: Icons.sell_outlined,
            title: 'Aucun véhicule à préparer',
            subtitle: 'Ajoutez un véhicule pour préparer sa fiche de revente.',
          );
        }
        final selected = vehicles.firstWhere(
          (v) => v.id == _selectedVehicleId,
          orElse: () => vehicles.first,
        );
        return Column(
          children: [
            if (vehicles.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final v in vehicles) ...[
                        ChoiceChip(
                          label: Text('${v.brand} ${v.model}'),
                          selected: v.id == selected.id,
                          onSelected: (_) =>
                              setState(() => _selectedVehicleId = v.id),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                    ],
                  ),
                ),
              ),
            Expanded(
              child: _ResaleSummary(key: ValueKey(selected.id), vehicle: selected),
            ),
          ],
        );
      },
    );
  }
}

class _ResaleSummary extends ConsumerWidget {
  const _ResaleSummary({super.key, required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completeness = ref.watch(vehicleCompletenessProvider(vehicle));
    final maintenanceAsync = ref.watch(vehicleMaintenanceProvider(vehicle.id));
    final documentsAsync = ref.watch(vehicleDocumentsProvider(vehicle.id));
    final remindersAsync = ref.watch(vehicleActiveRemindersProvider(vehicle.id));
    final mileageAsync = ref.watch(vehicleMileageHistoryProvider(vehicle.id));

    if (maintenanceAsync.isLoading ||
        documentsAsync.isLoading ||
        remindersAsync.isLoading ||
        mileageAsync.isLoading) {
      return const LoadingView();
    }
    final error = maintenanceAsync.error ??
        documentsAsync.error ??
        remindersAsync.error ??
        mileageAsync.error;
    if (error != null) {
      return const ErrorView(
          message: 'Impossible de charger ces données. Réessayez dans un instant.');
    }

    final maintenanceEntries = maintenanceAsync.value ?? const <MaintenanceEntry>[];
    final documents = documentsAsync.value ?? const <DocumentWithVersion>[];
    final activeReminders = remindersAsync.value ?? const <Reminder>[];
    final mileageHistory = mileageAsync.value ?? const <MileageEntry>[];

    final health = computeVehicleHealthScore(
      activeReminders: activeReminders,
      maintenanceEntries: maintenanceEntries,
      documents: documents,
      completeness: completeness,
    );
    final valuation = ref.read(valuationEngineProvider).compute(
          ValuationInput(
            brand: vehicle.brand,
            model: vehicle.model,
            trim: vehicle.trim,
            year: vehicle.year,
            firstRegistrationDate: vehicle.firstRegistrationDate,
            currentMileage: vehicle.currentMileage,
            fuelType: vehicle.fuelType,
            transmission: vehicle.transmission,
            condition: vehicle.condition,
            maintenanceEntryCount: maintenanceEntries.length,
          ),
        );
    final readiness = computeResaleReadiness(
      completeness: completeness,
      maintenanceEntries: maintenanceEntries,
      documents: documents,
      activeReminders: activeReminders,
      mileageHistory: mileageHistory,
    );
    final recommendations = buildResaleRecommendations(
      readiness: readiness,
      valuation: valuation,
      vehicle: vehicle,
    );

    return ListView(
      padding: EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, fabSafeBottomPadding(context)),
      children: [
        // V2.1 pass: the price is the priority of this screen (mockup's own
        // structure) - a slim title instead of a separate vehicle card
        // ahead of it, and the price card's own "PRIX CONSEILLÉ" tag
        // already labels it, so no redundant section header above it.
        Text('Revendre — ${vehicle.brand} ${vehicle.model}',
            style: Theme.of(context).textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: AppSpacing.sm),
        _EstimationCard(
          result: valuation,
          onExplain: () => showValuationBreakdownSheet(context, valuation),
        ),
        const SizedBox(height: AppSpacing.md),
        SectionHeader('Santé du carnet — ${health.score}/100'),
        const SizedBox(height: AppSpacing.xs),
        _HealthCard(health: health),
        const SizedBox(height: AppSpacing.md),
        const SectionHeader('Préparation à la vente'),
        const SizedBox(height: AppSpacing.xs),
        _ReadinessCard(readiness: readiness, recommendations: recommendations),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: () => _generatePdf(
            context,
            ref,
            vehicle: vehicle,
            health: health,
            valuation: valuation,
            readiness: readiness,
            maintenanceEntries: maintenanceEntries,
            documents: documents,
          ),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Générer le rapport PDF'),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }

  Future<void> _generatePdf(
    BuildContext context,
    WidgetRef ref, {
    required Vehicle vehicle,
    required VehicleHealthScore health,
    required ValuationResult valuation,
    required ResaleReadiness readiness,
    required List<MaintenanceEntry> maintenanceEntries,
    required List<DocumentWithVersion> documents,
  }) async {
    final profile = await ref.read(localProfileProvider.future);
    try {
      final bytes = await const ResalePdfReport().build(
        vehicle: vehicle,
        health: health,
        valuation: valuation,
        readiness: readiness,
        maintenanceEntries: maintenanceEntries,
        documents: documents,
        ownerName: profile?.displayName,
      );
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'dossier_revente_${vehicle.brand}_${vehicle.model}'
            .replaceAll(' ', '_'),
      );
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, 'Impossible de générer le PDF. Réessayez dans un instant.',
            icon: Icons.error_outline);
      }
    }
  }
}

/// "Prix conseillé" as the dominant, hero-sized figure (bloc design-review
/// 2026: "la valeur centrale doit avoir beaucoup plus d'impact visuel") -
/// Vente rapide/Prix haut are real numbers too, just visually secondary,
/// flanking it below instead of competing with it as three equal chips.
class _EstimationCard extends StatelessWidget {
  const _EstimationCard({required this.result, required this.onExplain});
  final ValuationResult result;
  final VoidCallback onExplain;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
            boxShadow: AppElevation.card(scheme),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sell_outlined, size: 13, color: scheme.primary),
                  const SizedBox(width: 5),
                  Text('PRIX CONSEILLÉ AUTOCARNET',
                      style: TextStyle(
                          color: scheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    text: formatAmount(result.fairPrice),
                    style: AppTypography.mono(context, fontSize: 32, fontWeight: FontWeight.w800),
                    children: [
                      TextSpan(
                        text: ' DH',
                        style: TextStyle(
                            fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _ConfidenceBadge(confidence: result.confidence),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: _TierChip(label: 'Vente rapide', value: formatCurrency(result.quickSale)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _TierChip(label: 'Prix haut', value: formatCurrency(result.highPrice)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Divider(color: scheme.outlineVariant.withValues(alpha: 0.6)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onExplain,
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                  child: const Text('Voir le détail du calcul', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Estimation AutoCarnet indicative — aucune cote de marché '
                        'externe (type Argus) n\'est connectée aujourd\'hui.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                const Divider(),
                Text('Confiance de l\'estimation', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                for (final factor in result.confidenceFactors)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          factor.satisfied ? Icons.check_circle_outline : Icons.circle_outlined,
                          size: 16,
                          color: factor.satisfied ? scheme.tertiary : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(factor.label, style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.confidence});
  final ConfidenceLevel confidence;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (confidence) {
      ConfidenceLevel.low => ('Confiance : faible', scheme.secondary),
      ConfidenceLevel.medium => ('Confiance : moyenne', scheme.onSurfaceVariant),
      ConfidenceLevel.good => ('Confiance : bonne', scheme.tertiary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

class _TierChip extends StatelessWidget {
  const _TierChip({required this.label, this.value});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            value ?? 'Indisponible',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: value != null
                ? AppTypography.mono(context, fontSize: 14, fontWeight: FontWeight.w700)
                : TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.health});
  final VehicleHealthScore health;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final level = healthLevelForScore(health.score);
    final levelColor = switch (level) {
      VehicleHealthLevel.good => scheme.tertiary,
      VehicleHealthLevel.attention => scheme.secondary,
      VehicleHealthLevel.critical => scheme.error,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: LinearProgressIndicator(
                value: health.score / 100,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
                color: levelColor,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final factor in health.factors)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      switch (factor.impact) {
                        HealthImpact.positive => Icons.check_circle_outline,
                        HealthImpact.negative => Icons.warning_amber_outlined,
                        HealthImpact.neutral => Icons.info_outline,
                      },
                      size: 18,
                      color: switch (factor.impact) {
                        HealthImpact.positive => scheme.tertiary,
                        HealthImpact.negative => scheme.secondary,
                        HealthImpact.neutral => scheme.onSurfaceVariant,
                      },
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(factor.label, style: Theme.of(context).textTheme.bodyMedium),
                          Text(factor.detail, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.readiness, required this.recommendations});
  final ResaleReadiness readiness;
  final List<String> recommendations;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in readiness.items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      item.ok ? Icons.check_circle : Icons.error_outline,
                      size: 18,
                      color: item.ok ? scheme.tertiary : scheme.error,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.label, style: Theme.of(context).textTheme.bodyMedium),
                          Text(item.detail, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (recommendations.isNotEmpty) ...[
              const Divider(),
              Text('Recommandations',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              for (final r in recommendations)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(child: Text(r, style: Theme.of(context).textTheme.bodySmall)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
