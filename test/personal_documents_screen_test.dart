import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/database/providers.dart';
import 'package:autocarnet/features/account/data/account_repository.dart';
import 'package:autocarnet/features/documents/data/document_repository.dart';
import 'package:autocarnet/features/documents/presentation/personal_documents_screen.dart';
import 'package:autocarnet/features/onboarding_lock/data/biometric_service.dart';
import 'package:autocarnet/features/onboarding_lock/data/pin_service.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/settings/presentation/settings_screen.dart';
import 'package:autocarnet/features/timeline/data/timeline_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeSignedInAccountRepository implements AccountRepository {
  @override
  User? get currentUser => User(
        id: 'adil',
        appMetadata: const {},
        userMetadata: null,
        aud: 'authenticated',
        email: 'adil@example.com',
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
  Future<String?> deviceAuthorizedUserId() async => 'adil';
  @override
  Future<String?> lastDeviceUserId() async => 'adil';
  @override
  Future<String?> deviceAuthorizedEmail() async => 'adil@example.com';
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

void main() {
  late AppDatabase db;
  late DocumentRepository documents;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final reminders = ReminderRepository(db);
    documents = DocumentRepository(db, TimelineRepository(db), reminders);
  });

  tearDown(() => db.close());

  List<Override> commonOverrides() => [
        appDatabaseProvider.overrideWithValue(db),
        accountRepositoryProvider.overrideWithValue(_FakeSignedInAccountRepository()),
      ];

  testWidgets('empty state invites adding a personal document', (tester) async {
    final container = ProviderContainer(overrides: commonOverrides());
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PersonalDocumentsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aucun document personnel'), findsOneWidget);
  });

  testWidgets('a permis de conduire already on file appears in the list with its expiry',
      (tester) async {
    await documents.createDocument(
      vehicleId: null,
      type: 'Permis de conduire',
      expiryDate: DateTime(2030, 6, 15),
      currentUserId: 'adil',
    );

    final container = ProviderContainer(overrides: commonOverrides());
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PersonalDocumentsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Permis de conduire'), findsOneWidget);
    expect(find.text('Expire le 15/6/2030'), findsOneWidget);
    expect(find.text('Aucun document personnel'), findsNothing);
  });

  testWidgets(
      '"Mes documents personnels" is reachable from Compte & sécurité and opens the '
      'dedicated screen', (tester) async {
    final container = ProviderContainer(overrides: [
      ...commonOverrides(),
      pinServiceProvider.overrideWithValue(_FakePinService()),
      biometricServiceProvider.overrideWithValue(_FakeBiometricService()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Mes documents personnels'), findsOneWidget);
    await tester.tap(find.text('Permis de conduire, pièce d\'identité...'));
    await tester.pumpAndSettle();

    expect(find.byType(PersonalDocumentsScreen), findsOneWidget);
  });
}
