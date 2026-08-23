import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/database/providers.dart';
import 'package:autocarnet/core/theme/app_theme.dart';
import 'package:autocarnet/features/account/data/account_repository.dart';
import 'package:autocarnet/features/onboarding_lock/data/biometric_service.dart';
import 'package:autocarnet/features/onboarding_lock/data/pin_service.dart';
import 'package:autocarnet/features/providers/presentation/providers_screen.dart';
import 'package:autocarnet/features/settings/presentation/settings_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeSignedInAccountRepository implements AccountRepository {
  @override
  User? get currentUser => User(
        id: 'user-1',
        appMetadata: const {},
        userMetadata: null,
        aud: 'authenticated',
        email: 'a@example.com',
        createdAt: DateTime.now().toIso8601String(),
      );
  @override
  Session? get currentSession => null;
  @override
  bool get isSignedIn => true;
  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();
  @override
  Future<String?> tryRestoreDeviceSession(String email) async => null;
  @override
  Future<void> sendEmailCode(String email) async {}
  @override
  Future<void> verifyEmailCode({required String email, required String code}) async {}
  @override
  Future<String> installationId() async => 'test-device';
  @override
  Future<String?> deviceAuthorizedUserId() async => 'user-1';
  @override
  Future<String?> lastDeviceUserId() async => 'user-1';
  @override
  Future<String?> deviceAuthorizedEmail() async => 'a@example.com';
  @override
  Future<void> registerThisDevice() async {}
  @override
  Future<bool> isDeviceStillAuthorized({required String userId}) async => true;
  @override
  Future<List<AuthorizedDevice>> listMyDevices() async => const [];
  @override
  Future<void> revokeDevice(String deviceRowId) async {}
  @override
  Future<void> disconnectFromThisDevice() async {}
  @override
  Future<void> disconnectFromAllDevices() async {}
}

class _FakePinService implements PinService {
  @override
  Future<bool> isPinSet(String accountId) async => true;
  @override
  Future<void> setPin(String accountId, String pin) async {}
  @override
  Future<bool> verifyPin(String accountId, String pin) async => false;
  @override
  Future<void> clearPin(String accountId) async {}
}

class _FakeBiometricService implements BiometricService {
  @override
  Future<bool> isDeviceSupported() async => false;
  @override
  Future<bool> isEnabled(String accountId) async => false;
  @override
  Future<void> setEnabled(String accountId, bool enabled) async {}
  @override
  Future<bool> authenticate() async => false;
}

/// Regression coverage for the reported bug: "Prestataires" and "Compte &
/// sécurité" (and, by the same root cause, every AppBar title in the app)
/// rendering as invisible white text on the near-white AppBar background.
/// Root cause was AppTheme._textTheme()'s `.copyWith(...)` block silently
/// dropping `color` on 8 TextStyle entries - these tests pump the REAL
/// [AppTheme.light] (most existing widget tests in this suite don't, since
/// they aren't testing visual/theme concerns) so a regression here would
/// actually be caught, not silently pass under Flutter's own default theme.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  testWidgets('"Prestataires" AppBar title is legible under the real app theme',
      (tester) async {
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      accountRepositoryProvider.overrideWithValue(_FakeSignedInAccountRepository()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light(), home: const ProvidersScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    final title = tester.widget<Text>(find.text('Prestataires'));
    final scheme = AppTheme.light().colorScheme;
    final resolvedColor =
        title.style?.color ?? DefaultTextStyle.of(tester.element(find.text('Prestataires'))).style.color;
    expect(resolvedColor, isNot(Colors.white));
    expect(resolvedColor, scheme.onSurface);
  });

  testWidgets('"Compte & sécurité" AppBar title is legible under the real app theme',
      (tester) async {
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      accountRepositoryProvider.overrideWithValue(_FakeSignedInAccountRepository()),
      pinServiceProvider.overrideWithValue(_FakePinService()),
      biometricServiceProvider.overrideWithValue(_FakeBiometricService()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light(), home: const SettingsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    final title = tester.widget<Text>(find.text('Compte & sécurité'));
    final scheme = AppTheme.light().colorScheme;
    final resolvedColor = title.style?.color ??
        DefaultTextStyle.of(tester.element(find.text('Compte & sécurité'))).style.color;
    expect(resolvedColor, isNot(Colors.white));
    expect(resolvedColor, scheme.onSurface);
  });
}
