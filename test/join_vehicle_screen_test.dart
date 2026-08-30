import 'package:autocarnet/core/sync/vehicle_sync_service.dart';
import 'package:autocarnet/features/sharing/data/sharing_models.dart';
import 'package:autocarnet/features/sharing/data/sharing_repository.dart';
import 'package:autocarnet/features/sharing/domain/vehicle_permission.dart';
import 'package:autocarnet/features/sharing/presentation/join_vehicle_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// `implements`, never `extends`: SharingRepository's real constructor
/// takes a SupabaseClient, which would try to touch Supabase in a test
/// environment - implementing the public interface directly (same pattern
/// already used for AccountRepository fakes elsewhere in this suite) means
/// this fake never needs one at all.
class _FakeSharingRepository implements SharingRepository {
  int previewCallCount = 0;
  int acceptCallCount = 0;
  InvitePreview? previewToReturn;
  InviteRedeemException? previewError;
  VehicleInvite? acceptToReturn;
  InviteRedeemException? acceptError;

  @override
  Future<InvitePreview> previewInvite(String rawInput) async {
    previewCallCount++;
    if (previewError != null) throw previewError!;
    return previewToReturn!;
  }

  @override
  Future<VehicleInvite> acceptInvite(String rawInput) async {
    acceptCallCount++;
    if (acceptError != null) throw acceptError!;
    return acceptToReturn!;
  }

  @override
  Future<VehicleInvite> createInvite({
    required String vehicleId,
    required VehiclePermission role,
    required InviteExpiry expiry,
  }) async =>
      throw UnimplementedError();
  @override
  Future<List<VehicleInvite>> listActiveInvites(String vehicleId) async => const [];
  @override
  Future<void> cancelInvite(String inviteId) async {}
  @override
  Future<List<VehicleMember>> listMembers(String vehicleId) async => const [];
  @override
  Future<void> updateMemberRole(String memberId, VehiclePermission role) async {}
  @override
  Future<void> revokeMember(String memberId) async {}
  @override
  Future<void> ensureOwnEmailSynced() async {}
}

class _NoopVehicleSyncService implements VehicleSyncService {
  @override
  Future<void> syncNow() async {}

  @override
  void Function(String stage, String message)? onStep;
}

InvitePreview _preview({bool alreadyMember = false, bool alreadyOwner = false}) => InvitePreview(
      vehicleId: 'veh-1',
      brand: 'Audi',
      model: 'Q5',
      ownerDisplayName: 'Adil',
      role: VehiclePermission.viewer,
      expiresAt: DateTime.now().add(const Duration(days: 7)),
      alreadyMember: alreadyMember,
      alreadyOwner: alreadyOwner,
    );

void main() {
  late _FakeSharingRepository fake;

  Future<void> pump(WidgetTester tester) async {
    fake = _FakeSharingRepository();
    final router = GoRouter(
      initialLocation: '/vehicles/join',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const Scaffold(body: Text('MES VEHICULES'))),
        GoRoute(path: '/vehicles/join', builder: (context, state) => const JoinVehicleScreen()),
        GoRoute(
          path: '/vehicles/:id',
          builder: (context, state) => Scaffold(body: Text('VEHICULE ${state.pathParameters['id']}')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharingRepositoryProvider.overrideWithValue(fake),
          vehicleSyncServiceProvider.overrideWithValue(_NoopVehicleSyncService()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  testWidgets('TEST 1: opening the screen shows the empty code form immediately - no backend call',
      (tester) async {
    await pump(tester);
    await tester.pump();

    expect(find.widgetWithText(TextField, 'Rejoindre un véhicule'), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(fake.previewCallCount, 0);
  });

  testWidgets('TEST 2: submitting an empty field shows a message and never calls the backend',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('Continuer'));
    await tester.pump();

    expect(find.text('Veuillez saisir un code de partage.'), findsOneWidget);
    expect(fake.previewCallCount, 0);
  });

  testWidgets('TEST 3: an invalid code shows the exact mandated message, no crash', (tester) async {
    await pump(tester);
    fake.previewError = const InviteRedeemException(InviteRedeemError.invalid);

    await tester.enterText(find.byType(TextField), 'BADCODE1');
    await tester.tap(find.text('Continuer'));
    await tester.pump();

    expect(find.text('Code de partage invalide.'), findsOneWidget);
  });

  testWidgets('TEST 4: a valid code shows the vehicle preview with its access level', (tester) async {
    await pump(tester);
    fake.previewToReturn = _preview();

    await tester.enterText(find.byType(TextField), 'GOODCODE');
    await tester.tap(find.text('Continuer'));
    await tester.pump();

    expect(find.text('Audi Q5'), findsOneWidget);
    expect(find.text('Consultation'), findsOneWidget);
    expect(find.text('Rejoindre ce véhicule'), findsOneWidget);
  });

  testWidgets(
      'confirming a successful join shows a real success screen and never bounces back to the '
      'code-entry form (regression: the join used to silently loop back to "Rejoindre un '
      'véhicule" after confirmation)', (tester) async {
    await pump(tester);
    fake.previewToReturn = _preview();
    fake.acceptToReturn = VehicleInvite(
      id: '',
      vehicleId: 'veh-1',
      rawCode: null,
      role: VehiclePermission.viewer,
      expiresAt: DateTime.now(),
      status: 'accepted',
    );

    await tester.enterText(find.byType(TextField), 'GOODCODE');
    await tester.tap(find.text('Continuer'));
    await tester.pump();
    await tester.tap(find.text('Rejoindre ce véhicule'));
    await tester.pump();

    expect(fake.acceptCallCount, 1);
    expect(find.text('Véhicule ajouté'), findsOneWidget);
    expect(find.textContaining('Audi Q5'), findsWidgets);
    expect(find.text('Rejoindre un véhicule', skipOffstage: false), findsWidgets,
        reason: 'this is only the AppBar title, not the code-entry form reappearing');
    expect(find.byType(TextField), findsNothing,
        reason: 'the code field must not reappear after a successful join');

    await tester.tap(find.text('Ouvrir le véhicule'));
    await tester.pumpAndSettle();
    expect(find.text('VEHICULE veh-1'), findsOneWidget);
  });

  testWidgets(
      'a failed confirmation stays on the preview step with a real error - it never silently '
      'discards the preview or falsely claims success (regression)', (tester) async {
    await pump(tester);
    fake.previewToReturn = _preview();
    fake.acceptError = const InviteRedeemException(InviteRedeemError.expired);

    await tester.enterText(find.byType(TextField), 'GOODCODE');
    await tester.tap(find.text('Continuer'));
    await tester.pump();
    await tester.tap(find.text('Rejoindre ce véhicule'));
    await tester.pump();

    expect(find.text('Ce code de partage a expiré.'), findsOneWidget);
    // Still on the preview - the vehicle card, and the ability to retry or
    // cancel, are still there. Never bounced silently to a blank form.
    expect(find.text('Audi Q5'), findsOneWidget);
    expect(find.text('Véhicule ajouté'), findsNothing);
  });

  testWidgets(
      'an unrecognized backend rejection never leaks the raw technical detail to the user - only '
      'a clear generic message, even though it is still carried on the exception for debug '
      'logging (spec: a raw SQL/Postgrest error must never reach an end user)', (tester) async {
    await pump(tester);
    fake.previewToReturn = _preview();
    fake.acceptError = const InviteRedeemException(
      InviteRedeemError.unknown,
      technicalDetail: '42702: column reference "vehicle_id" is ambiguous',
    );

    await tester.enterText(find.byType(TextField), 'GOODCODE');
    await tester.tap(find.text('Continuer'));
    await tester.pump();
    await tester.tap(find.text('Rejoindre ce véhicule'));
    await tester.pump();

    expect(find.textContaining('42702'), findsNothing);
    expect(find.textContaining('ambiguous'), findsNothing);
    expect(find.text('Impossible de rejoindre ce véhicule. Réessayez.'), findsOneWidget);
  });

  testWidgets('a recognized error (e.g. expired) never shows a technical detail, even if one is set',
      (tester) async {
    await pump(tester);
    fake.previewToReturn = _preview();
    fake.acceptError = const InviteRedeemException(
      InviteRedeemError.expired,
      technicalDetail: 'PGRST100: something internal',
    );

    await tester.enterText(find.byType(TextField), 'GOODCODE');
    await tester.tap(find.text('Continuer'));
    await tester.pump();
    await tester.tap(find.text('Rejoindre ce véhicule'));
    await tester.pump();

    expect(find.text('Ce code de partage a expiré.'), findsOneWidget);
    expect(find.textContaining('PGRST100'), findsNothing);
  });
}
