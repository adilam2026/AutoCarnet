import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/feedback.dart';
import '../../account/data/account_repository.dart';

/// "Appareils connectés" (spec bloc 13/14): every device authorized for
/// this account, with the ability to revoke one. Revoking forces that
/// device back through email/OTP the next time it checks in - see
/// AccountRepository.isDeviceStillAuthorized.
class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  late Future<List<AuthorizedDevice>> _devicesFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _devicesFuture = ref.read(accountRepositoryProvider).listMyDevices();
  }

  Future<void> _revoke(AuthorizedDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Révoquer cet appareil ?'),
        content: Text(
          '"${device.name}" ne pourra plus utiliser son code d\'accès local '
          'pour ouvrir AutoCarnet - une nouvelle vérification par email sera '
          'nécessaire.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Révoquer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(accountRepositoryProvider).revokeDevice(device.id);
    if (!mounted) return;
    setState(_load);
    showAppSnackBar(context, 'Appareil révoqué', icon: Icons.check_circle_outline);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Appareils connectés')),
      body: FutureBuilder<List<AuthorizedDevice>>(
        future: _devicesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: Text(
                  'Impossible de récupérer la liste des appareils. '
                  'Vérifiez votre connexion.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final devices = snapshot.data ?? const [];
          if (devices.isEmpty) {
            return const Center(child: Text('Aucun appareil enregistré.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: devices.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final device = devices[index];
              return Card(
                child: ListTile(
                  leading: Icon(device.isThisDevice ? Icons.smartphone : Icons.devices_other_outlined),
                  title: Text(device.name),
                  subtitle: Text(device.isThisDevice
                      ? 'Cet appareil'
                      : device.lastSeenAt != null
                          ? 'Dernière activité : ${device.lastSeenAt}'
                          : 'Activité inconnue'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Révoquer',
                    onPressed: () => _revoke(device),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
