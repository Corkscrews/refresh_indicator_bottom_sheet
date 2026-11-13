import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refresh_indicator_bottom_sheet_example/main.dart';

void main() {
  testWidgets('home opens a bottom sheet list', (tester) async {
    await tester.pumpWidget(const ExampleApp());

    await tester.tap(find.text('Open bottom sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Item 1'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);
  });
}
