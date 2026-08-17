import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/supabase_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding_lock/presentation/app_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Never blocks the offline-first experience: a device with no network at
  // first launch still reaches the app, account auth just isn't reachable
  // until connectivity returns (AccountRepository surfaces that state).
  // `publishableKey` expects the newer sb_publishable_... key format; this
  // project's Supabase key is still the legacy anon JWT, which `anonKey` is
  // guaranteed compatible with.
  // ignore: deprecated_member_use
  await Supabase.initialize(url: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey);
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
