import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/audit/presentation/audit_log_screen.dart';
import '../../features/dashboard/presentation/app_shell.dart';
import '../../features/documents/presentation/documents_tab.dart';
import '../../features/expenses/presentation/expenses_tab.dart';
import '../../features/fuel/presentation/fuel_tab.dart';
import '../../features/maintenance/presentation/maintenance_tab.dart';
import '../../features/providers/presentation/providers_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/sharing/presentation/join_vehicle_screen.dart';
import '../../features/timeline/presentation/timeline_tab.dart';
import '../../features/vehicles/presentation/screens/vehicle_create_screen.dart';
import '../../features/vehicles/presentation/screens/vehicle_home_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const AppShell()),
      GoRoute(
        path: '/vehicles/new',
        builder: (context, state) => const VehicleCreateScreen(),
      ),
      // Must come before '/vehicles/:id' below: go_router matches routes in
      // declaration order, and ':id' matches any single segment including
      // the literal "join" - if the dynamic route were declared first,
      // tapping "Rejoindre un véhicule" (which pushes '/vehicles/join')
      // would resolve to VehicleHomeScreen(vehicleId: 'join') instead of
      // this screen, never showing the code-entry form at all.
      GoRoute(
        path: '/vehicles/join',
        builder: (context, state) => const JoinVehicleScreen(),
      ),
      GoRoute(
        path: '/vehicles/:id',
        builder: (context, state) => VehicleHomeScreen(
          vehicleId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/vehicles/:id/documents',
        builder: (context, state) => DocumentsTab(
          vehicleId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/vehicles/:id/maintenance',
        builder: (context, state) => MaintenanceTab(
          vehicleId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/vehicles/:id/expenses',
        builder: (context, state) => ExpensesTab(
          vehicleId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/vehicles/:id/fuel',
        builder: (context, state) => FuelTab(
          vehicleId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/vehicles/:id/timeline',
        builder: (context, state) => TimelineTab(
          vehicleId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/providers',
        builder: (context, state) => const ProvidersScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/audit-log',
        builder: (context, state) => const AuditLogScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Page introuvable')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'Cette page n\'existe pas.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Retour à l\'accueil'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
});
