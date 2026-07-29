import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/dashboard/presentation/home_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/vehicles/presentation/screens/vehicle_create_screen.dart';
import '../../features/vehicles/presentation/screens/vehicle_detail_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/vehicles/new',
        builder: (context, state) => const VehicleCreateScreen(),
      ),
      GoRoute(
        path: '/vehicles/:id',
        builder: (context, state) => VehicleDetailScreen(
          vehicleId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});
