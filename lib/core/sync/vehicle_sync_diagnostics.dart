import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database.dart';
import 'vehicle_sync_service.dart';

/// Mission 2026, real-device incident report: a vehicle created while
/// genuinely signed in never reached Supabase, twice, and the owner has no
/// computer/adb to read `SYNC_VEHICLE 01-09` logs with. This runner drives
/// the REAL [VehicleSyncService.syncNow] for one vehicle (via its
/// [VehicleSyncService.onStep] observer hook - no duplicated/fake sync
/// logic, no change to the sync strategy itself) and turns its stage log
/// into a step-by-step report the diagnostic screen can render directly on
/// the phone.
///
/// Deliberately never infers "synced" from "no exception was thrown": step
/// 11 re-reads the local row after the run and only reports OK if
/// `syncStatus` is actually `synced`, and the screen's own "Vérifier dans
/// le cloud" action (see SyncDiagnosticsScreen) does a live Supabase SELECT
/// independent of this report entirely, so a local "synced" that doesn't
/// match reality in `public.vehicles` is still visible.
enum DiagnosticStepStatus { ok, failed, notRun }

class DiagnosticStep {
  const DiagnosticStep({
    required this.label,
    required this.status,
    this.at,
    this.detail,
  });

  final String label;
  final DiagnosticStepStatus status;
  final DateTime? at;
  final String? detail;
}

class VehicleSyncDiagnosticReport {
  const VehicleSyncDiagnosticReport({required this.ranAt, required this.steps});

  final DateTime ranAt;
  final List<DiagnosticStep> steps;
}

class _StageEvent {
  _StageEvent(this.stage, this.message, this.at);
  final String stage;
  final String message;
  final DateTime at;
}

class VehicleSyncDiagnosticRunner {
  VehicleSyncDiagnosticRunner(this._db, this._vehicleSync, this._clientFn);

  final AppDatabase _db;
  final VehicleSyncService _vehicleSync;
  final SupabaseClient Function() _clientFn;

  /// Runs the real pipeline for exactly one vehicle, right now, and reports
  /// exactly what happened - never a guess, never a replay of a past
  /// (unrecorded) attempt.
  Future<VehicleSyncDiagnosticReport> runFor(String vehicleId) async {
    final steps = <DiagnosticStep>[];

    final before = await (_db.select(_db.vehicles)..where((v) => v.id.equals(vehicleId)))
        .getSingleOrNull();
    final outboxBefore = await (_db.select(_db.syncOutbox)
          ..where((o) => o.entityType.equals('vehicle') & o.entityId.equals(vehicleId)))
        .getSingleOrNull();

    steps.add(DiagnosticStep(
      label: '1. Écriture SQLite locale',
      status: before != null ? DiagnosticStepStatus.ok : DiagnosticStepStatus.failed,
      at: before?.createdAt,
      detail: before == null
          ? 'véhicule introuvable localement (id: $vehicleId)'
          : 'créé localement le ${before.createdAt}',
    ));

    steps.add(DiagnosticStep(
      label: '2. Entrée outbox créée',
      status: (outboxBefore != null || before?.syncStatus == 'synced')
          ? DiagnosticStepStatus.ok
          : DiagnosticStepStatus.failed,
      at: outboxBefore?.createdAt,
      detail: outboxBefore != null
          ? 'opération "${outboxBefore.operation}", statut outbox actuel : '
              '"${outboxBefore.syncStatus}", tentatives : ${outboxBefore.retryCount}'
          : (before?.syncStatus == 'synced'
              ? 'aucune entrée (purgée après une confirmation antérieure réussie)'
              : 'ANOMALIE : aucune entrée outbox alors que le véhicule n\'est pas '
                  'marqué synced - la mise en file d\'attente a échoué ou a été '
                  'perdue'),
    ));

    final events = <_StageEvent>[];
    _vehicleSync.onStep = (stage, message) => events.add(_StageEvent(stage, message, DateTime.now()));
    final nudgeAt = DateTime.now();
    try {
      await _vehicleSync.syncNow();
    } finally {
      _vehicleSync.onStep = null;
    }

    _StageEvent? stage(String code) => events.where((e) => e.stage == code).firstOrNull;

    steps.add(DiagnosticStep(
      label: '3. Synchronisation déclenchée (nudge)',
      status: DiagnosticStepStatus.ok,
      at: nudgeAt,
      detail: 'VehicleSyncService.syncNow() invoqué depuis le diagnostic',
    ));

    final called = stage('01');
    steps.add(DiagnosticStep(
      label: '4. VehicleSyncService.syncNow() exécuté',
      status: called != null ? DiagnosticStepStatus.ok : DiagnosticStepStatus.notRun,
      at: called?.at,
    ));

    final noSession = stage('03');
    final sessionPresent = _clientFn().auth.currentSession != null;
    steps.add(DiagnosticStep(
      label: '5. Session Supabase disponible',
      status: noSession != null
          ? DiagnosticStepStatus.failed
          : (called != null ? DiagnosticStepStatus.ok : DiagnosticStepStatus.notRun),
      at: noSession?.at ?? called?.at,
      detail: noSession != null
          ? 'aucune session Supabase active (déconnecté, ou session expirée)'
          : (sessionPresent ? 'session active' : null),
    ));

    final connEvent = stage('04');
    final noConn = stage('05');
    steps.add(DiagnosticStep(
      label: '6. Connectivité réseau vérifiée',
      status: noConn != null
          ? DiagnosticStepStatus.failed
          : (connEvent != null ? DiagnosticStepStatus.ok : DiagnosticStepStatus.notRun),
      at: connEvent?.at,
      detail: connEvent?.message,
    ));

    final myUserId = _clientFn().auth.currentUser?.id;
    steps.add(DiagnosticStep(
      label: '7. user_id Supabase récupéré',
      status: connEvent == null
          ? DiagnosticStepStatus.notRun
          : (myUserId != null ? DiagnosticStepStatus.ok : DiagnosticStepStatus.failed),
      detail: myUserId ?? (connEvent != null ? 'aucun user_id malgré une session/connectivité OK' : null),
    ));

    final pushStarting = stage('06a');
    final wasPending = pushStarting?.message.contains(vehicleId) ?? false;
    steps.add(DiagnosticStep(
      label: '8. Requête INSERT/UPSERT envoyée à Supabase',
      status: pushStarting == null
          ? DiagnosticStepStatus.notRun
          : (wasPending ? DiagnosticStepStatus.ok : DiagnosticStepStatus.notRun),
      at: pushStarting?.at,
      detail: pushStarting == null
          ? null
          : (wasPending
              ? pushStarting.message
              : 'ce véhicule n\'était pas dans la liste des envois en attente '
                  '(${pushStarting.message}) - déjà marqué synced localement, '
                  'donc AUCUNE tentative d\'envoi n\'a eu lieu cette fois-ci'),
    ));

    final pushOk = stage('06b');
    final pushThrew = stage('06c');
    final confirmedThisVehicle = stage('06d')
        ?.let((e) => e.message.contains(vehicleId));
    steps.add(DiagnosticStep(
      label: '9. Réponse Supabase reçue',
      status: !wasPending
          ? DiagnosticStepStatus.notRun
          : (pushThrew != null
              ? DiagnosticStepStatus.failed
              : (pushOk != null ? DiagnosticStepStatus.ok : DiagnosticStepStatus.notRun)),
      at: (pushThrew ?? pushOk)?.at,
      detail: pushThrew?.message ?? pushOk?.message,
    ));

    steps.add(DiagnosticStep(
      label: '10. Ligne confirmée dans public.vehicles',
      status: !wasPending
          ? DiagnosticStepStatus.notRun
          : ((confirmedThisVehicle ?? false) ? DiagnosticStepStatus.ok : DiagnosticStepStatus.failed),
      at: (confirmedThisVehicle ?? false) ? stage('06d')?.at : null,
      detail: (confirmedThisVehicle ?? false)
          ? stage('06d')?.message
          : (wasPending
              ? 'aucune confirmation reçue pour ce véhicule précisément - vérifier '
                  '"Vérifier dans le cloud" ci-dessous pour la vérité terrain'
              : null),
    ));

    final after = await (_db.select(_db.vehicles)..where((v) => v.id.equals(vehicleId)))
        .getSingleOrNull();
    steps.add(DiagnosticStep(
      label: '11. Marqué "synced" localement',
      status: after?.syncStatus == 'synced' ? DiagnosticStepStatus.ok : DiagnosticStepStatus.failed,
      at: after?.updatedAt,
      detail: 'syncStatus local actuel : "${after?.syncStatus}"',
    ));

    return VehicleSyncDiagnosticReport(ranAt: DateTime.now(), steps: steps);
  }
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
