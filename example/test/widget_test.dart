import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refresh_indicator_bottom_sheet/refresh_indicator_bottom_sheet.dart';
import 'package:refresh_indicator_bottom_sheet_example/gesture_log.dart';
import 'package:refresh_indicator_bottom_sheet_example/main.dart';

void main() {
  testWidgets('home opens a bottom sheet list; the overlay logs a pull', (
    tester,
  ) async {
    // main() installs the log capture; the test pumps the app directly.
    debugRefreshSheetLogs = true;
    addTearDown(() => debugRefreshSheetLogs = false);
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) gestureLog.add(message);
    };

    await tester.pumpWidget(const ExampleApp());
    await tester.tap(find.text('Open bottom sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Item 1'), findsOneWidget);
    expect(find.byType(RefreshIndicatorOpt), findsOneWidget);

    await tester.drag(find.text('Item 2'), const Offset(0, 60));
    await tester.pump(const Duration(milliseconds: 200));
    expect(gestureLog.gestures, isNotEmpty);
    expect(find.textContaining('state='), findsOneWidget);

    await tester.tap(find.text('refresh'));
    expect(gestureLog.export(), contains('wanted=refresh'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    debugPrint = print; // checked before tear-downs run
  });
}
