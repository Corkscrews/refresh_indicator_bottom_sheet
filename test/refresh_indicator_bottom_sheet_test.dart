import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refresh_indicator_bottom_sheet/refresh_indicator_bottom_sheet.dart';

final _platforms = TargetPlatformVariant(<TargetPlatform>{
  TargetPlatform.android,
  TargetPlatform.iOS,
});

// On the 800x600 test screen the 9/16 sheet is 337.5 px tall, so the arm
// distance is ~84 px.

class _Harness {
  int refreshes = 0;
  Completer<void>? pending;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showRefreshModalBottomSheet<void>(
                  context: context,
                  builder: (_) => RefreshIndicatorOpt(
                    onRefresh: () {
                      refreshes++;
                      return (pending = Completer<void>()).future;
                    },
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: 30,
                      itemBuilder: (_, i) =>
                          ListTile(title: Text('Item ${i + 1}')),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> finishRefresh(WidgetTester tester) async {
    pending?.complete();
    await tester.pumpAndSettle();
  }
}

double _sheetTop(WidgetTester tester) =>
    tester.getTopLeft(find.byType(BottomSheet)).dy;

double _listOffset(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).last).position.pixels;

final _indicator = find.byType(RefreshProgressIndicator);

/// [by] moves in 10 px steps, 50 ms apart (200 px/s): a soft pull.
/// [fast] moves in 30 px steps, 16 ms apart (~1900 px/s).
class _Drag {
  _Drag(this.tester, this.gesture);

  final WidgetTester tester;
  final TestGesture gesture;
  var _time = Duration.zero;

  static Future<_Drag> start(WidgetTester tester, String item) async => _Drag(
    tester,
    await tester.startGesture(tester.getCenter(find.text(item))),
  );

  Future<void> by(double dy) async {
    for (var moved = 0.0; moved.abs() < dy.abs(); moved += 10.0 * dy.sign) {
      _time += const Duration(milliseconds: 50);
      await gesture.moveBy(Offset(0, 10.0 * dy.sign), timeStamp: _time);
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> fast(double dy) async {
    for (var moved = 0.0; moved < dy; moved += 30.0) {
      _time += const Duration(milliseconds: 16);
      await gesture.moveBy(const Offset(0, 30.0), timeStamp: _time);
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> up() async {
    _time += const Duration(milliseconds: 200);
    await gesture.up(timeStamp: _time);
    await tester.pump();
  }
}

void main() {
  testWidgets('RefreshIndicatorOpt builds a RefreshIndicator outside a sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RefreshIndicatorOpt(
          onRefresh: () async {},
          child: ListView(children: const [Text('Item')]),
        ),
      ),
    );

    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.text('Item'), findsOneWidget);
  });

  testWidgets('a soft short pull shows the indicator and leaves the sheet', (
    tester,
  ) async {
    final h = _Harness();
    await h.open(tester);
    final double openTop = _sheetTop(tester);

    final drag = await _Drag.start(tester, 'Item 2');
    await drag.by(50);
    expect(_indicator, findsOneWidget);
    expect(_sheetTop(tester), openTop);
    await drag.up();
    await tester.pumpAndSettle();

    expect(h.refreshes, 0);
    expect(_indicator, findsNothing);
    expect(_sheetTop(tester), openTop);
  }, variant: _platforms);

  testWidgets('a soft pull past the arm distance refreshes', (tester) async {
    final h = _Harness();
    await h.open(tester);
    final double openTop = _sheetTop(tester);

    final drag = await _Drag.start(tester, 'Item 2');
    await drag.by(120); // iOS loses ~29 px to slop and its motion threshold
    expect(_sheetTop(tester), openTop);
    await drag.up();
    await tester.pump(const Duration(milliseconds: 300));

    expect(h.refreshes, 1);
    expect(_indicator, findsOneWidget); // spinning while onRefresh runs
    await h.finishRefresh(tester);
    expect(_indicator, findsNothing);
    expect(_sheetTop(tester), openTop);
  }, variant: _platforms);

  testWidgets(
    'a fast pull hands over to the sheet, which then tracks the finger',
    (tester) async {
      final h = _Harness();
      await h.open(tester);
      final double openTop = _sheetTop(tester);

      final drag = await _Drag.start(tester, 'Item 2');
      await drag.fast(120);
      final double taken = _sheetTop(tester);
      expect(taken, greaterThan(openTop));
      await drag.by(50);
      expect(_sheetTop(tester), moreOrLessEquals(taken + 50, epsilon: 0.5));
      expect(_listOffset(tester), 0.0);
      await drag.up();
      await tester.pumpAndSettle();

      expect(h.refreshes, 0);
    },
    variant: _platforms,
  );

  testWidgets('a short sheet drag springs back without refreshing', (
    tester,
  ) async {
    final h = _Harness();
    await h.open(tester);
    final double openTop = _sheetTop(tester);

    final drag = await _Drag.start(tester, 'Item 2');
    await drag.fast(120);
    await drag.by(10); // the finger stops before lifting
    await drag.up();
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(_sheetTop(tester), moreOrLessEquals(openTop, epsilon: 0.5));
    expect(h.refreshes, 0);
  }, variant: _platforms);

  testWidgets('a fast start then a slow drag past half closes the sheet', (
    tester,
  ) async {
    final h = _Harness();
    await h.open(tester);
    final double height = tester.getSize(find.byType(BottomSheet)).height;

    final drag = await _Drag.start(tester, 'Item 2');
    await drag.fast(120);
    await drag.by(height * 0.6);
    await drag.up();
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(h.refreshes, 0);
  }, variant: _platforms);

  testWidgets('once armed, a slow pull that speeds up still refreshes', (
    tester,
  ) async {
    final h = _Harness();
    await h.open(tester);
    final double openTop = _sheetTop(tester);

    final drag = await _Drag.start(tester, 'Item 2');
    await drag.by(120);
    await drag.fast(150);
    expect(_sheetTop(tester), openTop);
    await drag.up();
    await tester.pump(const Duration(milliseconds: 300));

    expect(h.refreshes, 1);
    await h.finishRefresh(tester);
    expect(_sheetTop(tester), openTop);
  }, variant: _platforms);

  testWidgets('a fast pull closes the sheet without refreshing', (
    tester,
  ) async {
    final h = _Harness();
    await h.open(tester);

    await tester.fling(find.text('Item 2'), const Offset(0, 200), 2000);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(h.refreshes, 0);
  }, variant: _platforms);

  testWidgets('reversing hands the same pointer back to the list', (
    tester,
  ) async {
    final h = _Harness();
    await h.open(tester);
    final double openTop = _sheetTop(tester);

    final drag = await _Drag.start(tester, 'Item 2');
    await drag.fast(120);
    expect(_sheetTop(tester), greaterThan(openTop));
    await drag.by(-300);
    expect(_sheetTop(tester), moreOrLessEquals(openTop, epsilon: 0.5));
    expect(_listOffset(tester), greaterThan(50));
    await drag.up();
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(h.refreshes, 0);
  }, variant: _platforms);

  testWidgets('a drag that starts mid-list moves neither indicator nor sheet', (
    tester,
  ) async {
    final h = _Harness();
    await h.open(tester);
    final double openTop = _sheetTop(tester);

    var drag = await _Drag.start(tester, 'Item 4');
    await drag.by(-150);
    await drag.up();
    await tester.pumpAndSettle();
    expect(_listOffset(tester), greaterThan(0));

    drag = await _Drag.start(tester, 'Item 6');
    await drag.by(300);
    expect(_sheetTop(tester), openTop);
    expect(_indicator, findsNothing);
    await drag.up();
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(h.refreshes, 0);
  }, variant: _platforms);

  testWidgets(
    'while refreshing, a pull moves the sheet and never refreshes again',
    (tester) async {
      final h = _Harness();
      await h.open(tester);
      final double openTop = _sheetTop(tester);

      var drag = await _Drag.start(tester, 'Item 2');
      await drag.by(120); // iOS loses ~29 px to slop and its motion threshold
      await drag.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(h.refreshes, 1);

      drag = await _Drag.start(tester, 'Item 2');
      await drag.by(60);
      expect(_sheetTop(tester), greaterThan(openTop));
      await drag.up();
      await tester.pump(const Duration(milliseconds: 500));
      expect(_sheetTop(tester), moreOrLessEquals(openTop, epsilon: 0.5));

      await h.finishRefresh(tester);
      expect(h.refreshes, 1);
    },
    variant: _platforms,
  );
}
