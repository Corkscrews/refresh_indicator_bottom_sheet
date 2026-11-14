import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'arbitration.dart';
import 'debug_log.dart';
import 'refresh_sheet_route.dart';

/// What the scroll bridge needs from the widget that owns the list. Keeping
/// this narrow lets the scroll classes stay independent of the widget state.
abstract interface class SheetDragHost {
  /// The route the list sits in, or null outside a [RefreshSheetRoute].
  RefreshSheetRoute<dynamic>? get route;

  /// The arbitrator that splits every drag delta.
  RefreshSheetArbitrator get arbitrator;

  /// Whether a refresh is running.
  bool get refreshing;

  /// Height of the enclosing sheet, or 0 if there is none.
  double sheetHeight();

  /// Mirrors the arbitrator's pull on screen.
  void syncIndicator();

  /// Acts on what the arbitrator decided at release.
  void commit(ArbitrationCommit commit);
}

/// The list's scroll controller inside a [RefreshSheetRoute]. Its positions
/// route every drag through the arbitrator.
class SheetScrollController extends ScrollController {
  SheetScrollController(this.host);

  final SheetDragHost host;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    refreshSheetLog(
      'scroll position created: the list uses the package controller '
      '(physics=${physics.runtimeType})',
    );
    return _SheetScrollPosition(
      host: host,
      // A short list must still take user offsets at its top, as in
      // _CupertinoSheetScrollController.
      physics: physics.applyTo(const AlwaysScrollableScrollPhysics()),
      context: context,
      oldPosition: oldPosition,
    );
  }
}

/// Hands every drag delta to the arbitrator and applies its split, the seam
/// `_CupertinoSheetScrollPosition` uses in cupertino/sheet.dart.
class _SheetScrollPosition extends ScrollPositionWithSingleContext {
  _SheetScrollPosition({
    required this.host,
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  final SheetDragHost host;

  bool _restAtDown = true;
  bool _active = false;
  double _sheetHeight = 0.0;
  double _written = 0.0; // last sheet offset applied to the route controller

  @override
  ScrollHoldController hold(VoidCallback holdCancelCallback) {
    // A finger that catches a moving or bouncing list only stops it.
    _restAtDown = !(activity?.isScrolling ?? false);
    refreshSheetLog(
      'hold: activity=${activity.runtimeType} restAtDown=$_restAtDown '
      'pixels=${_px(pixels)}',
    );
    return super.hold(holdCancelCallback);
  }

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    final RefreshSheetRoute<dynamic>? route = host.route;
    final Drag drag = super.drag(details, dragCancelCallback);
    if (route == null) return drag;
    _sheetHeight = host.sheetHeight();
    final bool eligible = _isEligible(route, details);
    _logDragStart(route, eligible, details);
    _beginArbitration(route, eligible);
    _written = host.arbitrator.sheetOffset;
    _restAtDown = true;
    _active = true;
    return drag;
  }

  @override
  void applyUserOffset(double delta) {
    if (!_active) {
      super.applyUserOffset(delta);
      return;
    }
    final RefreshSheetArbitrator arbitrator = host.arbitrator;
    final double toList = arbitrator.route(
      delta,
      room: pixels - minScrollExtent,
    );
    _applySheetOffset();
    host.syncIndicator();
    if (toList != 0.0) super.applyUserOffset(toList);
    if (debugRefreshSheetLogs) {
      refreshSheetLog(
        'delta ${_px(delta)} -> list ${_px(toList)} | ${arbitrator.describe()}',
      );
    }
  }

  @override
  void goBallistic(double velocity) {
    if (!_active) {
      super.goBallistic(velocity);
      return;
    }
    _active = false;
    // ScrollDragController.end negates the finger velocity.
    final ArbitrationCommit commit = host.arbitrator.release(-velocity);
    host.commit(commit);
    // Only the list's own release flings the list.
    super.goBallistic(commit == ArbitrationCommit.list ? velocity : 0.0);
  }

  bool _isEligible(
    RefreshSheetRoute<dynamic> route,
    DragStartDetails details,
  ) =>
      route.isCurrent &&
      _restAtDown &&
      _kArbitratedKinds.contains(details.kind) &&
      // The arbitrator reads a positive delta as finger down.
      axisDirection == AxisDirection.down &&
      pixels <= minScrollExtent + host.arbitrator.config.edgeSlop;

  void _beginArbitration(RefreshSheetRoute<dynamic> route, bool eligible) {
    host.arbitrator.beginDrag(
      eligible: eligible,
      sheetEntering: route.entering,
      refreshing: host.refreshing,
      sheetEnabled: route.enableDrag && route.isCurrent,
      viewport: viewportDimension,
      sheetHeight: _sheetHeight,
      sheetOffset: (1.0 - route.sheetController.value) * _sheetHeight,
    );
  }

  /// Moves the route's controller to the arbitrator's sheet offset, but only
  /// when that offset has changed since it was last written.
  void _applySheetOffset() {
    final double sheetOffset = host.arbitrator.sheetOffset;
    if (sheetOffset != _written && !host.route!.exiting) {
      // Stock _handleDragUpdate formula, in pixels owned by the sheet.
      host.route!.sheetController.value = 1.0 - sheetOffset / _sheetHeight;
      _written = sheetOffset;
    }
  }

  void _logDragStart(
    RefreshSheetRoute<dynamic> route,
    bool eligible,
    DragStartDetails details,
  ) {
    refreshSheetLog(
      'drag start: eligible=$eligible | isCurrent=${route.isCurrent} '
      'restAtDown=$_restAtDown kind=${details.kind} pixels=${_px(pixels)} '
      'min=${_px(minScrollExtent)} enableDrag=${route.enableDrag} '
      'sheetValue=${route.sheetController.value.toStringAsFixed(logFractionDigits)}',
    );
  }
}

String _px(double value) => value.toStringAsFixed(logPixelDigits);

/// Mouse and trackpad drags only scroll the list.
const Set<PointerDeviceKind?> _kArbitratedKinds = <PointerDeviceKind?>{
  PointerDeviceKind.touch,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
};
