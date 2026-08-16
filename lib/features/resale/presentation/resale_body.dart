import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
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
      error: (e, _) => ErrorView(message: e.toString()),
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
    if (error != null) return ErrorView(message: error.toString());

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
            registrationDatePrecision: vehicle.firstRegistrationDatePrecision,
            currentMileage: vehicle.currentMileage,
            fuelType: vehicle.fuelType,
            transmission: vehicle.transmission,
            purchasePrice: vehicle.purchasePrice,
            acquisitionDate: vehicle.acquisitionDate,
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
          AppSpacing.md, AppSpacing.md, AppSpacing.md, fabSafeBottomPadding(context)),
      children: [
        _VehicleHeaderCard(vehicle: vehicle),
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader('Estimation de revente'),
        const SizedBox(height: AppSpacing.sm),
        _EstimationCard(
          result: valuation,
          onExplain: () => showValuationBreakdownSheet(context, valuation),
        ),
        const SizedBox(height: AppSpacing.lg),
        SectionHeader('Santé du carnet — ${health.score}/100'),
        const SizedBox(height: AppSpacing.sm),
        _HealthCard(health: health),
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader('Préparation à la vente'),
        const SizedBox(height: AppSpacing.sm),
        _ReadinessCard(readiness: readiness, recommendations: recommendations),
        const SizedBox(height: AppSpacing.lg),
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
        showAppSnackBar(context, 'Impossible de générer le PDF : $e',
            icon: Icons.error_outline);
      }
    }
  }
}

class _VehicleHeaderCard extends StatelessWidget {
  const _VehicleHeaderCard({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.directions_car, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${vehicle.brand} ${vehicle.model}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    '${vehicle.currentMileage.toStringAsFixed(0)} km'
                    '${vehicle.year != null ? ' • ${vehicle.year}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
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

class _EstimationCard extends StatelessWidget {
  const _EstimationCard({required this.result, required this.onExplain});
  final ValuationResult result;
  final VoidCallback onExplain;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _TierChip(
                        label: 'Vente rapide', value: result.quickSale.toStringAsFixed(0)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _TierChip(
                        label: 'Prix conseillé',
                        value: result.fairPrice.toStringAsFixed(0),
                        highlight: true),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _TierChip(
                        label: 'Prix haut', value: result.highPrice.toStringAsFixed(0)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                _ConfidenceBadge(confidence: result.confidence),
                const Spacer(),
                TextButton(
                  onPressed: onExplain,
                  child: const Text('Comment cette estimation est calculée ?'),
                ),
              ],
            ),
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
                      color: factor.satisfied ? Colors.green : scheme.onSurfaceVariant,
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
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.confidence});
  final ConfidenceLevel confidence;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (confidence) {
      ConfidenceLevel.low => ('Confiance : faible', Colors.orange),
      ConfidenceLevel.medium => ('Confiance : moyenne', Colors.blue),
      ConfidenceLevel.good => ('Confiance : bonne', Colors.green),
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
  const _TierChip({required this.label, this.value, this.highlight = false});
  final String label;
  final String? value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: highlight ? scheme.primaryContainer.withValues(alpha: 0.5) : scheme.surfaceContainerHigh,
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
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: value == null ? scheme.onSurfaceVariant : null,
                ),
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
                color: health.score >= 70
                    ? Colors.green
                    : (health.score >= 40 ? Colors.orange : scheme.error),
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
                        HealthImpact.positive => Colors.green,
                        HealthImpact.negative => Colors.orange,
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
                      color: item.ok ? Colors.green : scheme.error,
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
