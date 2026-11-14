import 'dart:math' as math;

import 'package:flutter/gestures.dart';

import 'arbitration_config.dart';
import 'debug_log.dart';
import 'pointer_history.dart';

export 'arbitration_config.dart';

/// Who tracks the finger.
enum ArbitrationState { idle, list, indicator, sheet }

/// What a release commits to.
enum ArbitrationCommit { list, retract, refresh, close, springBack }

/// Upper bound on state changes inside one delta; guards against cycling.
const int _kMaxRouteHops = 8;

/// A delta being split between the targets, one state change at a time.
class _RouteSplit {
  _RouteSplit(this.rest, this.room);

  /// Finger movement not yet routed.
  double rest;

  /// How far the list can still scroll toward its top.
  double room;

  /// The part the list must apply.
  double toList = 0.0;
}

/// Decides, delta by delta, whether the list, the refresh indicator or the
/// sheet takes a drag. Pure state: no widgets, no side effects.
///
/// Feed it raw pointer samples ([pointerDown], [pointerMove], [pointerUp]),
/// start each scroll drag with [beginDrag], distribute every delta with
/// [route], and end with [release]. [pull] and [sheetOffset] are the
/// indicator's and the sheet's tracked pixels.
class RefreshSheetArbitrator {
  RefreshSheetArbitrator({
    this.config = const RefreshSheetArbitrationConfig(),
    this.onLog,
  });

  RefreshSheetArbitrationConfig config;
  final void Function(String message)? onLog;

  ArbitrationState state = ArbitrationState.idle;

  /// Px owned by the indicator in this gesture.
  double pull = 0.0;

  /// Px the sheet is dragged down from fully open.
  double sheetOffset = 0.0;

  bool get armed => _armed;
  double get armDistance => _armDistance;

  final PointerHistory _history = PointerHistory();

  // The current drag.
  bool _eligible = false;
  bool _refreshing = false;
  bool _sheetEnabled = false;
  bool _topBand = false;
  bool _armed = false;
  bool _cancelled = false;
  double _armDistance = 0.0;
  double _sheetHeight = 0.0;

  void pointerDown(
    int pointer,
    Duration time,
    Offset position,
    Offset local,
    PointerDeviceKind kind,
  ) => _history.down(pointer, time, position, local, kind);

  void pointerMove(int pointer, Duration time, Offset position) =>
      _history.move(
        pointer,
        time,
        position,
        reversalHysteresis: config.reversalHysteresis,
      );

  void pointerUp(int pointer) => _history.up(pointer);

  /// A cancelled pointer never refreshes and never closes. The scroll
  /// recognizer reports an accepted drag's cancel as a normal end, so the
  /// cancel must be recorded here.
  void pointerCancel(int pointer) {
    _cancelled = true;
    _history.up(pointer);
  }

  /// Starts a scroll drag. [eligible] means the list was at rest at its top
  /// when the finger landed; an ineligible drag only ever scrolls the list.
  /// [sheetEntering] means the sheet is off home because its entry animation
  /// is still running, not because a drag left it there.
  void beginDrag({
    required bool eligible,
    bool sheetEntering = false,
    required bool refreshing,
    required bool sheetEnabled,
    required double viewport,
    required double sheetHeight,
    required double sheetOffset,
  }) {
    _eligible = eligible;
    _refreshing = refreshing;
    _sheetEnabled = sheetEnabled && sheetHeight > 0.0;
    _armDistance = config.armDistanceFraction * viewport;
    _sheetHeight = sheetHeight;
    _topBand = _history.downLocal.dy < config.topBandFraction * viewport;
    _armed = false;
    _cancelled = false;
    pull = 0.0;
    this.sheetOffset = sheetOffset;
    state = _initialState(sheetOffset, sheetEntering);
    _log(
      'begin: state=${state.name} eligible=$eligible refreshing=$refreshing '
      'sheetEnabled=$_sheetEnabled band=${_topBand ? 'top' : 'body'} '
      'V=${viewport.toStringAsFixed(logPixelDigits)} '
      'H=${sheetHeight.toStringAsFixed(logPixelDigits)} '
      'arm=${_armDistance.toStringAsFixed(logPixelDigits)}',
    );
  }

  /// Splits one finger delta (positive = finger down) between the targets.
  /// [room] is how far the list can still scroll toward its top. Updates
  /// [pull] and [sheetOffset], and returns the part the list must apply.
  double route(double delta, {required double room}) {
    final _RouteSplit split = _RouteSplit(delta, room);
    for (var hops = 0; split.rest != 0.0 && hops < _kMaxRouteHops; hops++) {
      _routeStep(split);
    }
    return split.toList;
  }

  /// Commits whatever is tracking. [fingerVelocity] is px/s, positive down.
  ArbitrationCommit release(double fingerVelocity) {
    final ArbitrationCommit commit = _commitFor(fingerVelocity);
    _log(
      'release: ${state.name} -> ${commit.name} | '
      'v=${fingerVelocity.toStringAsFixed(logPixelDigits)} '
      'pull=${pull.toStringAsFixed(logPixelDigits)} '
      'sheet=${sheetOffset.toStringAsFixed(logPixelDigits)} '
      'cancelled=$_cancelled',
    );
    state = ArbitrationState.idle;
    return commit;
  }

  /// One line with every input the takeover decision reads.
  String describe() {
    final Offset run = _history.run;
    final int elapsedMs =
        (_history.lastTime - _history.downTime).inMilliseconds;
    return 't=${elapsedMs}ms state=${state.name}${_armed ? '(armed)' : ''} '
        'pull=${pull.toStringAsFixed(logPixelDigits)} '
        'sheet=${sheetOffset.toStringAsFixed(logPixelDigits)} '
        'vSmooth=${_history.smoothedVy.toStringAsFixed(logSpeedDigits)} '
        'vInst=${_history.instantVy.toStringAsFixed(logSpeedDigits)} '
        'run=${run.dy.toStringAsFixed(logPixelDigits)}/'
        '${run.dx.toStringAsFixed(logPixelDigits)} '
        'straight=${_history.straightness.toStringAsFixed(logRatioDigits)} '
        'flips=${_history.flipCount} multi=${_history.multiTouch}';
  }

  ArbitrationState _initialState(double sheetOffset, bool sheetEntering) {
    if (!_eligible) return ArbitrationState.list;
    // Catching a sheet that is springing back keeps dragging it; catching the
    // entry animation is a fresh pull, which must not move the sheet slowly.
    return sheetOffset > 0.0 && _sheetEnabled && !sheetEntering
        ? ArbitrationState.sheet
        : ArbitrationState.idle;
  }

  void _routeStep(_RouteSplit split) {
    switch (state) {
      case ArbitrationState.idle:
        _routeFromIdle(split);
      case ArbitrationState.list:
        _routeToList(split);
      case ArbitrationState.indicator:
        _routeToIndicator(split);
      case ArbitrationState.sheet:
        _routeToSheet(split);
    }
  }

  /// The first delta of a drag picks its target.
  void _routeFromIdle(_RouteSplit split) {
    final bool atTop = split.room <= config.edgeSlop;
    _enter(
      split.rest > 0.0 && atTop ? _topTarget() : ArbitrationState.list,
      'first delta',
    );
  }

  /// The list scrolls while it can; past its top the remainder moves on.
  void _routeToList(_RouteSplit split) {
    if (split.rest < 0.0 || !_eligible) {
      split.toList += split.rest;
      split.room -= split.rest;
      split.rest = 0.0;
      return;
    }
    final double take = math.min(split.rest, math.max(0.0, split.room));
    split.toList += take;
    split.room -= take;
    split.rest -= take;
    if (split.rest > 0.0) _overflowFromList(split);
  }

  /// The list reached its top with finger movement left over.
  void _overflowFromList(_RouteSplit split) {
    final ArbitrationState next = _topTarget();
    if (next == ArbitrationState.list) {
      split.toList += split.rest; // platform overscroll
      split.rest = 0.0;
    } else {
      _enter(next, 'list reached its top');
    }
  }

  /// The indicator tracks the pull; a fast downward run hands it to the sheet.
  void _routeToIndicator(_RouteSplit split) {
    if (split.rest > 0.0 && _dismissIntent()) {
      _enter(ArbitrationState.sheet, 'dismiss intent');
      return;
    }
    pull += split.rest;
    split.rest = 0.0;
    if (pull < 0.0) {
      split.rest = pull;
      pull = 0.0;
      _enter(ArbitrationState.list, 'indicator unwound');
    }
    _updateArmed();
  }

  /// Keeps [_armed] in step with the pull, with hysteresis on the way down.
  void _updateArmed() {
    if (!_armed && pull >= _armDistance) {
      _armed = true;
      _log('armed at pull ${pull.toStringAsFixed(logPixelDigits)}');
    } else if (_armed && pull < _armDistance - config.armHysteresis) {
      _armed = false;
      _log('disarmed at pull ${pull.toStringAsFixed(logPixelDigits)}');
    }
  }

  /// The sheet takes the delta up to its full height; past home it moves on.
  void _routeToSheet(_RouteSplit split) {
    sheetOffset = math.min(sheetOffset + split.rest, _sheetHeight);
    split.rest = 0.0;
    if (sheetOffset < 0.0) {
      split.rest = sheetOffset;
      sheetOffset = 0.0;
      _enter(
        _refreshing ? ArbitrationState.list : ArbitrationState.indicator,
        'sheet home',
      );
    }
  }

  ArbitrationCommit _commitFor(double fingerVelocity) {
    return switch (state) {
      ArbitrationState.idle || ArbitrationState.list => ArbitrationCommit.list,
      ArbitrationState.indicator =>
        _armed && !_cancelled
            ? ArbitrationCommit.refresh
            : ArbitrationCommit.retract,
      ArbitrationState.sheet =>
        !_cancelled && _sheetCloses(fingerVelocity)
            ? ArbitrationCommit.close
            : ArbitrationCommit.springBack,
    };
  }

  bool _sheetCloses(double fingerVelocity) =>
      fingerVelocity >= config.closeVelocity ||
      sheetOffset >= config.closeProgress * _sheetHeight;

  ArbitrationState _topTarget() {
    if (!_refreshing) return ArbitrationState.indicator;
    return _sheetEnabled ? ArbitrationState.sheet : ArbitrationState.list;
  }

  void _enter(ArbitrationState next, String reason) {
    _log('${state.name} -> ${next.name} ($reason) | ${describe()}');
    state = next;
  }

  /// A fast, straight downward run from an indicator pull hands it to the
  /// sheet.
  bool _dismissIntent() {
    // Armed, or tracked past the deadline, means committed to the indicator.
    final bool committed =
        _armed ||
        _history.lastTime - _history.downTime > config.takeoverDeadline;
    if (!_sheetEnabled ||
        (committed && !config.refreshCanBecomeDismiss) ||
        _history.multiTouch ||
        _history.runDir <= 0) {
      return false;
    }
    return _isVerticalRun() && _passesVelocityGate();
  }

  bool _isVerticalRun() {
    final Offset run = _history.run;
    return run.dy.abs() >= config.axisDominance * run.dx.abs() &&
        _history.straightness >= config.minStraightness;
  }

  bool _passesVelocityGate() {
    final double gate = _topBand
        ? config.dismissVelocityTop
        : config.dismissVelocityBody;
    return _history.lastTime - _history.downTime >= config.velocityHoldOff &&
        _history.run.dy >= config.minRunForVelocity &&
        _history.flipCount < config.jitterFlips &&
        _history.smoothedVy >= gate &&
        _history.instantVy >= config.instantVelocityFactor * gate;
  }

  void _log(String message) => onLog?.call(message);
}
