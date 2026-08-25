import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/providers.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../../core/sync/sync_outbox_repository.dart';
import '../../../core/utils/currency_format.dart';
import '../../../core/utils/id_generator.dart';
import '../../timeline/data/timeline_repository.dart';

class ExpenseStats {
  final double totalAll;
  final double thisMonth;
  final double thisYear;
  final Map<String, double> byCategory;
  const ExpenseStats({
    required this.totalAll,
    required this.thisMonth,
    required this.thisYear,
    required this.byCategory,
  });

  static const empty = ExpenseStats(
    totalAll: 0,
    thisMonth: 0,
    thisYear: 0,
    byCategory: {},
  );
}

class ExpenseRepository {
  ExpenseRepository(this._db, this._timeline, [this._sync, this._outbox]);
  final AppDatabase _db;
  final TimelineRepository _timeline;
  // Optional (sync-hardening pass, after the GLC data-loss report) - see
  // VehicleRepository's identical fields for the full rationale.
  final SyncCoordinator? _sync;
  final SyncOutboxRepository? _outbox;

  void _nudgeSync() {
    unawaited(_sync?.syncAll());
  }

  // Awaited, unlike _nudgeSync - see VehicleRepository's identical helper
  // for why (a local SQLite write, not a network call).
  Future<void> _enqueueOutbox(String expenseId, String operation) {
    return _outbox?.enqueue(entityType: 'expense', entityId: expenseId, operation: operation) ??
        Future.value();
  }

  Future<Expense?> getById(String id) {
    return (_db.select(_db.expenses)..where((e) => e.id.equals(id))).getSingleOrNull();
  }

  Stream<List<Expense>> watchForVehicle(String vehicleId) {
    final query = _db.select(_db.expenses)
      ..where((e) => e.vehicleId.equals(vehicleId) & e.isDeleted.equals(false))
      ..orderBy([(e) => OrderingTerm.desc(e.date)]);
    return query.watch();
  }

  Future<String> createExpense({
    required String vehicleId,
    required String category,
    required DateTime date,
    required double amount,
    String currency = 'MAD',
    String? providerId,
    double? mileage,
    String? paymentMethod,
    String? comments,
  }) async {
    final id = newId();
    final now = DateTime.now();
    await _db.into(_db.expenses).insert(
          ExpensesCompanion.insert(
            id: id,
            vehicleId: vehicleId,
            category: category,
            date: date,
            amount: amount,
            currency: Value(currency),
            providerId: Value(providerId),
            mileage: Value(mileage),
            paymentMethod: Value(paymentMethod),
            comments: Value(comments),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _timeline.logEvent(
      vehicleId: vehicleId,
      moduleOrigin: 'expenses',
      eventType: 'expense_added',
      title: '$category — ${formatAmount(amount)} $currency',
      linkedEntityId: id,
      linkedEntityType: 'expense',
      occurredAt: date,
    );
    await _enqueueOutbox(id, 'create');
    _nudgeSync();
    return id;
  }

  /// Only ever called for a standalone expense (no linkedMaintenanceId/
  /// linkedFuelId) - one generated from an operation must be edited from
  /// that operation instead, so its amount always matches the source.
  Future<void> updateExpense({
    required String id,
    required String vehicleId,
    required String category,
    required DateTime date,
    required double amount,
    String currency = 'MAD',
    String? providerId,
    double? mileage,
    String? paymentMethod,
    String? comments,
  }) async {
    await (_db.update(_db.expenses)..where((e) => e.id.equals(id))).write(
      ExpensesCompanion(
        category: Value(category),
        date: Value(date),
        amount: Value(amount),
        currency: Value(currency),
        providerId: Value(providerId),
        mileage: Value(mileage),
        paymentMethod: Value(paymentMethod),
        comments: Value(comments),
        updatedAt: Value(DateTime.now()),
        // Sync-hardening pass: without this, editing an already-synced
        // expense would silently never reach the cloud again.
        syncStatus: const Value('pendingSync'),
      ),
    );
    // Same eventType/linkedEntityId as creation: logEvent upserts in place.
    await _timeline.logEvent(
      vehicleId: vehicleId,
      moduleOrigin: 'expenses',
      eventType: 'expense_added',
      title: '$category — ${formatAmount(amount)} $currency',
      linkedEntityId: id,
      linkedEntityType: 'expense',
      occurredAt: date,
    );
    await _enqueueOutbox(id, 'update');
    _nudgeSync();
  }

  Future<void> softDelete(String id) async {
    await (_db.update(_db.expenses)..where((e) => e.id.equals(id))).write(
      ExpensesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pendingSync'),
      ),
    );
    await _timeline.removeForEntity('expense', id);
    await _enqueueOutbox(id, 'delete');
    _nudgeSync();
  }

  /// RG-DEP-003: statistics are always scoped to a single vehicle, never
  /// consolidated across the fleet.
  ExpenseStats computeStats(List<Expense> expenses) {
    if (expenses.isEmpty) return ExpenseStats.empty;
    final now = DateTime.now();
    double total = 0, month = 0, year = 0;
    final byCategory = <String, double>{};
    for (final e in expenses) {
      total += e.amount;
      if (e.date.year == now.year) {
        year += e.amount;
        if (e.date.month == now.month) month += e.amount;
      }
      byCategory.update(e.category, (v) => v + e.amount,
          ifAbsent: () => e.amount);
    }
    return ExpenseStats(
      totalAll: total,
      thisMonth: month,
      thisYear: year,
      byCategory: byCategory,
    );
  }
}

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(timelineRepositoryProvider),
    ref.watch(syncCoordinatorProvider),
    ref.watch(syncOutboxRepositoryProvider),
  );
});

final vehicleExpensesProvider =
    StreamProvider.family<List<Expense>, String>((ref, vehicleId) {
  return ref.watch(expenseRepositoryProvider).watchForVehicle(vehicleId);
});

final vehicleExpenseStatsProvider =
    Provider.family<AsyncValue<ExpenseStats>, String>((ref, vehicleId) {
  final expenses = ref.watch(vehicleExpensesProvider(vehicleId));
  return expenses.whenData(
    (list) => ref.watch(expenseRepositoryProvider).computeStats(list),
  );
});
