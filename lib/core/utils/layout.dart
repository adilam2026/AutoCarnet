import 'package:flutter/material.dart';

/// Bottom padding for scrollable content that sits under a
/// FloatingActionButton, accounting for the device's own system inset
/// (gesture nav bar / iOS home indicator) instead of a fixed guess.
double fabSafeBottomPadding(BuildContext context) {
  return 88 + MediaQuery.of(context).padding.bottom;
}

/// showModalBottomSheet's `useSafeArea` only ever protects the TOP of the
/// sheet (`SafeArea(bottom: false, ...)` - see bottom_sheet.dart). Every
/// sheet in this app must add this to its own bottom padding, on top of
/// `viewInsets.bottom` for the keyboard, or its lowest button ends up
/// behind the Android gesture bar / iOS home indicator.
double sheetSystemBottomInset(BuildContext context) {
  return MediaQuery.of(context).padding.bottom;
}
