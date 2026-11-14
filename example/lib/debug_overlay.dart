import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:refresh_indicator_bottom_sheet_example/gesture_log.dart';

/// Live arbitrator state, plus buttons to label the last gesture and copy
/// the session. Polls the log, since lines also arrive during build.
class DebugOverlay extends StatefulWidget {
  const DebugOverlay({super.key});

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final log = gestureLog;
    final last = log.gestures.isEmpty ? null : log.gestures.last;
    const style = TextStyle(
      color: Colors.white,
      fontSize: 10,
      fontFamily: 'monospace',
    );
    Widget tag(String label) => TextButton(
      style: TextButton.styleFrom(
        foregroundColor: last?.label == label
            ? Colors.amberAccent
            : Colors.white,
        visualDensity: VisualDensity.compact,
      ),
      onPressed: () => setState(() => log.label(label)),
      child: Text(label),
    );
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Material(
          color: Colors.black.withValues(alpha: 0.75),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(log.live, style: style),
                Text(log.transition, style: style),
                Text(log.release, style: style),
                Row(
                  children: <Widget>[
                    Text('wanted:', style: style),
                    tag('refresh'),
                    tag('dismiss'),
                    tag('scroll'),
                    const Spacer(),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: log.export())),
                      child: Text('copy ${log.gestures.length}'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
