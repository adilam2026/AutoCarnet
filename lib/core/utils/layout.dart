import 'package:flutter/material.dart';

/// Bottom padding for scrollable content that sits under a
/// FloatingActionButton, accounting for the device's own system inset
/// (gesture nav bar / iOS home indicator) instead of a fixed guess.
double fabSafeBottomPadding(BuildContext context) {
  return 88 + MediaQuery.of(context).padding.bottom;
}
