import 'package:autocarnet/core/database/tables.dart';
import 'package:autocarnet/core/theme/app_theme.dart';
import 'package:autocarnet/features/documents/presentation/document_status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DocumentStatusChip renders a label for every status',
      (tester) async {
    for (final status in DocumentVersionStatus.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: DocumentStatusChip(status: status)),
        ),
      );
      expect(find.byType(DocumentStatusChip), findsOneWidget);
    }
  });
}
