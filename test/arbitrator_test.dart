import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refresh_indicator_bottom_sheet/src/arbitration.dart';

// V = 400 -> arm distance 100, top band below 132 px. H = 450.
const double _viewport = 400.0;
const double _sheetHeight = 450.0;

/// Replays one pointer through the arbitrator, the way the Listener and the
/// scroll position feed it.
class _Trace {
  _Trace({
    double localY = 50.0,
    bool eligible = true,
    bool refreshing = false,
    bool sheetEnabled = true,
  }) {
    arb.pointerDown(1, _t, _at, Offset(200.0, localY), PointerDeviceKind.touch);
    arb.beginDrag(
      eligible: eligible,
      refreshing: refreshing,
      sheetEnabled: sheetEnabled,
      viewport: _viewport,
      sheetHeight: _sheetHeight,
      sheetOffset: 0.0,
    );
  }

  final arb = RefreshSheetArbitrator();
  Duration _t = Duration.zero;
  Offset _at = const Offset(200.0, 300.0);
  double room = 0.0; // list pixels above its top
  double listTotal = 0.0;

  /// [steps] moves of [dy] (and [dx]) px, [ms] apart.
  void move(int steps, double dy, {int ms = 16, double dx = 0.0}) {
    for (var i = 0; i < steps; i++) {
      _t += Duration(milliseconds: ms);
      _at += Offset(dx, dy);
      arb.pointerMove(1, _t, _at);
      final double toList = arb.route(dy, room: room);
      room -= toList;
      listTotal += toList;
    }
  }

  void pause(int ms) => _t += Duration(milliseconds: ms);

  ArbitrationCommit release(double velocity) => arb.release(velocity);
}

void main() {
  testWidgets('soft short pull drives the indicator only', (_) async {
    final trace = _Trace()..move(10, 5.0); // 312 px/s, 50 px
    expect(trace.arb.state, ArbitrationState.indicator);
    expect(trace.arb.pull, 50.0);
    expect(trace.arb.sheetOffset, 0.0);
    expect(trace.arb.armed, isFalse);
    expect(trace.release(300.0), ArbitrationCommit.retract);
  });

  testWidgets('soft pull past the arm distance refreshes on release', (
    _,
  ) async {
    final trace = _Trace()..move(24, 5.0); // 120 px
    expect(trace.arb.armed, isTrue);
    expect(trace.arb.state, ArbitrationState.indicator);
    expect(trace.release(300.0), ArbitrationCommit.refresh);
  });

  testWidgets('fast pull hands the pointer to the sheet mid-gesture', (
    _,
  ) async {
    final trace = _Trace()..move(8, 30.0); // 1875 px/s
    expect(trace.arb.state, ArbitrationState.sheet);
    expect(trace.arb.pull, lessThan(trace.arb.armDistance));
    expect(trace.arb.sheetOffset, greaterThan(0.0));
    expect(trace.arb.pull + trace.arb.sheetOffset, 240.0); // nothing lost
    expect(trace.release(1875.0), ArbitrationCommit.close);
  });

  testWidgets('a fast pull from the body uses the lower velocity gate', (
    _,
  ) async {
    final top = _Trace()..move(8, 15.0); // 937 px/s
    final body = _Trace(localY: 300.0)..move(8, 15.0);
    expect(top.arb.state, ArbitrationState.indicator);
    expect(body.arb.state, ArbitrationState.sheet);
  });

  testWidgets('a slow pull never hands over, however long', (_) async {
    final trace = _Trace()..move(60, 5.0); // 300 px
    expect(trace.arb.state, ArbitrationState.indicator);
    expect(trace.arb.sheetOffset, 0.0);
    expect(trace.release(300.0), ArbitrationCommit.refresh);
  });

  testWidgets('once armed, speeding up stays a refresh', (_) async {
    final trace = _Trace()..move(22, 5.0); // 110 px, armed
    expect(trace.arb.armed, isTrue);
    trace.move(5, 40.0); // 2500 px/s
    expect(trace.arb.state, ArbitrationState.indicator);
    expect(trace.arb.sheetOffset, 0.0);
    expect(trace.release(2500.0), ArbitrationCommit.refresh);
  });

  testWidgets('reversal unwinds sheet, then indicator, then scrolls the list', (
    _,
  ) async {
    final trace = _Trace()..move(8, 30.0); // fast: the sheet takes over
    expect(trace.arb.state, ArbitrationState.sheet);

    trace.move(50, -5.0); // 250 px back up
    expect(trace.arb.sheetOffset, 0.0);
    expect(trace.arb.pull, 0.0);
    expect(trace.arb.state, ArbitrationState.list);
    expect(trace.listTotal, -10.0);

    trace.move(4, 5.0); // back down: the list returns to its top first
    expect(trace.listTotal, 0.0);
    expect(trace.arb.state, ArbitrationState.indicator);
    expect(trace.arb.pull, 10.0);
  });

  testWidgets('with a refresh running, a top pull goes straight to the sheet', (
    _,
  ) async {
    final trace = _Trace(refreshing: true)..move(3, 5.0);
    expect(trace.arb.state, ArbitrationState.sheet);
    expect(trace.arb.sheetOffset, 15.0);
    expect(trace.arb.pull, 0.0);
  });

  testWidgets('an ineligible gesture only scrolls the list', (_) async {
    final trace = _Trace(eligible: false)..move(20, 30.0);
    expect(trace.arb.state, ArbitrationState.list);
    expect(trace.listTotal, 600.0);
    expect(trace.release(1875.0), ArbitrationCommit.list);
  });

  testWidgets('a diagonal fast pull never moves the sheet', (_) async {
    final trace = _Trace()..move(4, 25.0, dx: 60.0); // 100 px down
    expect(trace.arb.state, ArbitrationState.indicator);
    expect(trace.arb.sheetOffset, 0.0);
  });

  testWidgets('a second finger freezes takeovers', (_) async {
    final trace = _Trace();
    trace.arb.pointerDown(
      2,
      Duration.zero,
      Offset.zero,
      Offset.zero,
      PointerDeviceKind.touch,
    );
    trace.move(8, 30.0);
    expect(trace.arb.state, ArbitrationState.indicator);
  });

  testWidgets('enableDrag: false keeps every pull on the indicator', (_) async {
    final trace = _Trace(sheetEnabled: false)..move(10, 30.0);
    expect(trace.arb.state, ArbitrationState.indicator);
    expect(trace.release(1875.0), ArbitrationCommit.refresh);
  });

  testWidgets('an upward start scrolls the list', (_) async {
    final trace = _Trace()..move(3, -10.0);
    expect(trace.arb.state, ArbitrationState.list);
    expect(trace.listTotal, -30.0);
  });
}
