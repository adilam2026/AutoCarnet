import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/database/providers.dart';
import 'package:autocarnet/features/account/data/account_repository.dart';
import 'package:autocarnet/features/documents/presentation/document_form_sheet.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeSignedInAccountRepository implements AccountRepository {
  @override
  User? get currentUser => User(
        id: 'me',
        appMetadata: const {},
        userMetadata: null,
        aud: 'authenticated',
        email: 'me@example.com',
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
  Future<String?> deviceAuthorizedUserId() async => 'me';
  @override
  Future<String?> lastDeviceUserId() async => 'me';
  @override
  Future<String?> deviceAuthorizedEmail() async => 'me@example.com';
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

/// Regression coverage for the mission bug: opening a contextual "Ajouter
/// X" entry point (Administratif -> Ajouter Assurance) used to still show
/// the full generic document-type picker, forcing the user to pick a type
/// they'd already chosen by tapping that specific button. Only the truly
/// generic "Documents -> Ajouter un document" entry point should ever show
/// that picker.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<void> pumpSheet(WidgetTester tester, {String? initialType, String? vehicleId}) async {
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      accountRepositoryProvider.overrideWithValue(_FakeSignedInAccountRepository()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showDocumentFormSheet(
                    context,
                    vehicleId: vehicleId ?? 'vehicle-1',
                    initialType: initialType,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'CONTEXTUEL: "Ajouter Assurance" opens directly on the Assurance form - '
      'no "Type *" picker, no other document type ever shown', (tester) async {
    await pumpSheet(tester, initialType: 'Assurance');

    expect(find.text('Type *'), findsNothing);
    expect(find.text('Carte grise'), findsNothing);
    expect(find.text('Vignette'), findsNothing);
    expect(find.textContaining('Assurance'), findsWidgets);
    // Assurance keeps its provider/cost fields.
    expect(find.text('Compagnie d\'assurance'), findsOneWidget);
    expect(find.text('Coût'), findsOneWidget);
  });

  testWidgets(
      'GÉNÉRIQUE: "Documents -> Ajouter un document" (no initialType) still '
      'shows the full type picker', (tester) async {
    await pumpSheet(tester);

    expect(find.text('Type *'), findsOneWidget);
  });

  testWidgets('CONTEXTUEL "Ajouter Carte grise": no expiry date, no cost, no '
      'provider field - only what actually applies', (tester) async {
    await pumpSheet(tester, initialType: 'Carte grise');

    expect(find.text('Type *'), findsNothing);
    // "Carte grise" has no default renewal, so the expiry button would
    // still show its unfilled placeholder if present at all - it must not
    // be there.
    expect(find.text('Date d\'expiration'), findsNothing);
    expect(find.textContaining('Expire :'), findsNothing);
    expect(find.text('Coût'), findsNothing);
    expect(find.text('Organisme / prestataire'), findsNothing);
    // The single relevant date field stays - already pre-filled to today.
    expect(find.textContaining('Délivré :'), findsOneWidget);
  });

  testWidgets(
      'CONTEXTUEL "Ajouter Permis de conduire" (driver document, no vehicle): '
      'no provider, no cost, but expiry date stays (permis can expire)',
      (tester) async {
    await pumpSheet(tester, initialType: 'Permis de conduire', vehicleId: null);

    expect(find.text('Type *'), findsNothing);
    expect(find.text('Coût'), findsNothing);
    expect(find.text('Organisme / prestataire'), findsNothing);
    expect(find.textContaining('Délivré :'), findsOneWidget);
    // Permis de conduire has a 120-month default renewal, so the expiry
    // button is pre-filled ("Expire : ...") rather than showing its
    // unfilled placeholder - either way, it must be present.
    expect(find.textContaining('Expire :'), findsOneWidget);
  });

  testWidgets(
      'CONTEXTUEL "Ajouter Visite technique": provider field relabelled '
      '"Centre de contrôle", no cost field', (tester) async {
    await pumpSheet(tester, initialType: 'Visite technique');

    expect(find.text('Type *'), findsNothing);
    expect(find.text('Centre de contrôle'), findsOneWidget);
    expect(find.text('Coût'), findsNothing);
  });

  testWidgets('CONTEXTUEL "Ajouter Vignette": no provider field, cost field '
      'stays (montant éventuel), civil-year picker shown', (tester) async {
    await pumpSheet(tester, initialType: 'Vignette');

    expect(find.text('Type *'), findsNothing);
    expect(find.text('Organisme / prestataire'), findsNothing);
    expect(find.text('Coût'), findsOneWidget);
    expect(find.text('Année de la vignette *'), findsOneWidget);
  });
}
