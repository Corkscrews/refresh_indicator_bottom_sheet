import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:refresh_indicator_bottom_sheet/refresh_indicator_bottom_sheet.dart';
import 'package:refresh_indicator_bottom_sheet_example/debug_overlay.dart';
import 'package:refresh_indicator_bottom_sheet_example/gesture_log.dart';
import 'package:refresh_indicator_bottom_sheet_example/home_screen.dart';

void main() {
  debugRefreshSheetLogs = true; // the tuning overlay reads the [RSheet] lines
  final DebugPrintCallback print = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) gestureLog.add(message);
    print(message, wrapWidth: wrapWidth);
  };
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const HomeScreen(),
      builder: (context, child) =>
          Stack(children: <Widget>[child!, const DebugOverlay()]),
    );
  }
}
