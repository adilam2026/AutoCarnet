import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding_lock/presentation/app_gate.dart';

void main() {
  runApp(const ProviderScope(child: AutoCarnetApp()));
}

class AutoCarnetApp extends ConsumerWidget {
  const AutoCarnetApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'AutoCarnet',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      builder: (context, child) =>
          AppGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
