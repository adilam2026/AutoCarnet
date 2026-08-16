import 'package:flutter/material.dart';

/// Consistent success/info snackbar so every save/delete action gives the
/// user a visible confirmation (Principe: no silent operations).
void showAppSnackBar(BuildContext context, String message, {IconData? icon}) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.onInverseSurface),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}
