import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

/// Every threshold the pull-to-refresh / drag-to-dismiss arbitration uses.
///
/// `V` is the list viewport height and `H` the sheet height. Values marked as
/// hypotheses are starting points to be tuned by the experiments in
/// docs/analysis/refresh-vs-dismiss-arbitration.md, section 7.
@immutable
class RefreshSheetArbitrationConfig {
  const RefreshSheetArbitrationConfig({
    this.edgeSlop = 1.0,
    this.topBandFraction = 0.33,
    this.axisDominance = 2.0,
    this.minStraightness = 0.85,
    this.reversalHysteresis = 8.0,
    this.velocityHoldOff = const Duration(milliseconds: 40),
    this.takeoverDeadline = const Duration(milliseconds: 200),
    this.refreshCanBecomeDismiss = false,
    this.minRunForVelocity = 32.0,
    this.dismissVelocityTop = 1100.0,
    this.dismissVelocityBody = 800.0,
    this.instantVelocityFactor = 0.5,
    this.jitterFlips = 2,
    this.armDistanceFraction = 0.25,
    this.armHysteresis = 12.0,
    this.closeVelocity = 700.0,
    this.closeProgress = 0.5,
    this.indicatorTravelFactor = 1.5,
    this.snapDuration = const Duration(milliseconds: 150),
    this.retractDuration = const Duration(milliseconds: 200),
  });

  /// Px from the list's min extent that still counts as "at the top".
  final double edgeSlop;

  /// A pointer that lands in this top fraction of `V` uses the top thresholds.
  final double topBandFraction;

  /// The run is vertical when `|dy| >= axisDominance * |dx|`.
  final double axisDominance;

  /// Minimum net displacement / path length of the run.
  final double minStraightness;

  /// Px of opposite movement before a new run starts.
  final double reversalHysteresis;

  /// No velocity decision before this much time since pointer down.
  final Duration velocityHoldOff;

  /// No takeover after this much time since pointer down: a pull the
  /// indicator has been tracking stays with the indicator, however it speeds
  /// up. A dismiss flick starts moving right after the finger lands.
  final Duration takeoverDeadline;

  /// When true, a pull the indicator is tracking (armed or past
  /// [takeoverDeadline]) still hands over to the sheet if it turns fast.
  final bool refreshCanBecomeDismiss;

  /// No velocity decision before the run is this long, in px.
  final double minRunForVelocity;

  /// Smoothed downward px/s that hands an indicator pull to the sheet, top band.
  final double dismissVelocityTop;

  /// Same, for a pointer that landed below the top band.
  final double dismissVelocityBody;

  /// The last sample's velocity must be at least this fraction of the gate.
  final double instantVelocityFactor;

  /// This many direction flips within the velocity window means jitter; the
  /// velocity gate is then ignored.
  final int jitterFlips;

  /// Pull that arms the refresh, as a fraction of `V`
  /// (stock `_kDragContainerExtentPercentage`).
  final double armDistanceFraction;

  /// Px below the arm distance before an armed indicator disarms.
  final double armHysteresis;

  /// Downward release px/s that closes a dragged sheet (stock `_kMinFlingVelocity`).
  final double closeVelocity;

  /// Dragged fraction of `H` that closes on release (stock `_kCloseProgressThreshold`).
  final double closeProgress;

  /// Indicator travel at full pull, in (displacement + indicator size)
  /// (stock `_kDragSizeFactorLimit`).
  final double indicatorTravelFactor;

  /// Indicator snap to its refresh position, and retract on cancel or takeover.
  final Duration snapDuration;

  /// Indicator exit after the refresh completes.
  final Duration retractDuration;
}

/// Who tracks the finger.
enum ArbitrationState { idle, list, indicator, sheet }

/// What a release commits to.
enum ArbitrationCommit { list, retract, refresh, close, springBack }

// VelocityTracker's horizon (gestures/velocity_tracker.dart).
const Duration _kVelocityWindow = Duration(milliseconds: 100);

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

  // Pointer samples.
  int _pointers = 0;
  int? _primary;
  bool _multiTouch = false;
  Duration _downTime = Duration.zero;
  Offset _downLocal = Offset.zero;
  VelocityTracker _tracker = VelocityTracker.withKind(PointerDeviceKind.touch);
  Offset _last = Offset.zero;
  Duration _lastTime = Duration.zero;
  double _instantVy = 0.0;
  int _lastStepSign = 0;
  final List<Duration> _flips = <Duration>[];

  // The current run: movement since the last reversal.
  Offset _runStart = Offset.zero;
  Offset _runExtreme = Offset.zero;
  int _runDir = 0;
  double _runPath = 0.0;

  // The current drag.
  bool _eligible = false;
  bool _refreshing = false;
  bool _sheetEnabled = false;
  bool _topBand = false;
  bool _armed = false;
  double _armDistance = 0.0;
  double _sheetHeight = 0.0;

  void pointerDown(
    int pointer,
    Duration time,
    Offset position,
    Offset local,
    PointerDeviceKind kind,
  ) {
    _pointers++;
    if (_pointers > 1) {
      _multiTouch = true; // freezes takeovers until every finger lifts
      return;
    }
    _primary = pointer;
    _multiTouch = false;
    _downTime = time;
    _downLocal = local;
    _tracker = VelocityTracker.withKind(kind)..addPosition(time, position);
    _last = position;
    _lastTime = time;
    _instantVy = 0.0;
    _lastStepSign = 0;
    _flips.clear();
    _runStart = position;
    _runExtreme = position;
    _runDir = 0;
    _runPath = 0.0;
  }

  void pointerMove(int pointer, Duration time, Offset position) {
    if (pointer != _primary) return;
    _tracker.addPosition(time, position);
    final Offset step = position - _last;
    final double dt =
        (time - _lastTime).inMicroseconds / Duration.microsecondsPerSecond;
    if (dt > 0) _instantVy = step.dy / dt;

    final int sign = step.dy.sign.toInt();
    if (sign != 0) {
      if (_lastStepSign != 0 && sign != _lastStepSign) _flips.add(time);
      _lastStepSign = sign;
    }
    _flips.removeWhere((flip) => time - flip > _kVelocityWindow);

    if (_runDir == 0) {
      _runDir = (position.dy - _runStart.dy).sign.toInt();
      _runExtreme = position;
      _runPath += step.distance;
    } else if ((position.dy - _runExtreme.dy) * _runDir >= 0) {
      _runExtreme = position;
      _runPath += step.distance;
    } else if ((_runExtreme.dy - position.dy) * _runDir >
        config.reversalHysteresis) {
      _runStart = _runExtreme;
      _runExtreme = position;
      _runDir = -_runDir;
      _runPath = (position - _runStart).distance;
    } else {
      _runPath += step.distance;
    }

    _last = position;
    _lastTime = time;
  }

  void pointerUp(int pointer) {
    _pointers = math.max(0, _pointers - 1);
  }

  /// Starts a scroll drag. [eligible] means the list was at rest at its top
  /// when the finger landed; an ineligible drag only ever scrolls the list.
  void beginDrag({
    required bool eligible,
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
    _topBand = _downLocal.dy < config.topBandFraction * viewport;
    _armed = false;
    pull = 0.0;
    this.sheetOffset = sheetOffset;
    state = !eligible
        ? ArbitrationState.list
        : (sheetOffset > 0.0 && _sheetEnabled
              ? ArbitrationState.sheet
              : ArbitrationState.idle);
    _log(
      'begin: state=${state.name} eligible=$eligible refreshing=$refreshing '
      'sheetEnabled=$_sheetEnabled band=${_topBand ? 'top' : 'body'} '
      'V=${viewport.toStringAsFixed(1)} H=${sheetHeight.toStringAsFixed(1)} '
      'arm=${_armDistance.toStringAsFixed(1)}',
    );
  }

  /// Splits one finger delta (positive = finger down) between the targets.
  /// [room] is how far the list can still scroll toward its top. Updates
  /// [pull] and [sheetOffset], and returns the part the list must apply.
  double route(double delta, {required double room}) {
    var rest = delta;
    var toList = 0.0;
    for (var hops = 0; rest != 0.0 && hops < 8; hops++) {
      switch (state) {
        case ArbitrationState.idle:
          _enter(
            rest > 0.0 && room <= config.edgeSlop
                ? _topTarget()
                : ArbitrationState.list,
            'first delta',
          );
        case ArbitrationState.list:
          if (rest < 0.0 || !_eligible) {
            toList += rest;
            room -= rest;
            rest = 0.0;
            break;
          }
          final double take = math.min(rest, math.max(0.0, room));
          toList += take;
          room -= take;
          rest -= take;
          if (rest > 0.0) {
            final next = _topTarget();
            if (next == ArbitrationState.list) {
              toList += rest; // platform overscroll
              rest = 0.0;
            } else {
              _enter(next, 'list reached its top');
            }
          }
        case ArbitrationState.indicator:
          if (rest > 0.0 && _dismissIntent()) {
            _enter(ArbitrationState.sheet, 'dismiss intent');
            break;
          }
          pull += rest;
          rest = 0.0;
          if (pull < 0.0) {
            rest = pull;
            pull = 0.0;
            _enter(ArbitrationState.list, 'indicator unwound');
          }
          if (!_armed && pull >= _armDistance) {
            _armed = true;
            _log('armed at pull ${pull.toStringAsFixed(1)}');
          } else if (_armed && pull < _armDistance - config.armHysteresis) {
            _armed = false;
            _log('disarmed at pull ${pull.toStringAsFixed(1)}');
          }
        case ArbitrationState.sheet:
          sheetOffset = math.min(sheetOffset + rest, _sheetHeight);
          rest = 0.0;
          if (sheetOffset < 0.0) {
            rest = sheetOffset;
            sheetOffset = 0.0;
            _enter(
              _refreshing ? ArbitrationState.list : ArbitrationState.indicator,
              'sheet home',
            );
          }
      }
    }
    return toList;
  }

  /// Commits whatever is tracking. [fingerVelocity] is px/s, positive down.
  ArbitrationCommit release(double fingerVelocity, {bool cancelled = false}) {
    final ArbitrationCommit commit = switch (state) {
      ArbitrationState.idle || ArbitrationState.list => ArbitrationCommit.list,
      ArbitrationState.indicator =>
        _armed && !cancelled
            ? ArbitrationCommit.refresh
            : ArbitrationCommit.retract,
      ArbitrationState.sheet =>
        !cancelled &&
                (fingerVelocity >= config.closeVelocity ||
                    sheetOffset >= config.closeProgress * _sheetHeight)
            ? ArbitrationCommit.close
            : ArbitrationCommit.springBack,
    };
    _log(
      'release: ${state.name} -> ${commit.name} | v=${fingerVelocity.toStringAsFixed(1)} '
      'pull=${pull.toStringAsFixed(1)} sheet=${sheetOffset.toStringAsFixed(1)} cancelled=$cancelled',
    );
    state = ArbitrationState.idle;
    return commit;
  }

  /// One line with every input the takeover decision reads.
  String describe() {
    final Offset run = _last - _runStart;
    return 't=${(_lastTime - _downTime).inMilliseconds}ms state=${state.name}${_armed ? '(armed)' : ''} pull=${pull.toStringAsFixed(1)} '
        'sheet=${sheetOffset.toStringAsFixed(1)} vSmooth=${_smoothedVy.toStringAsFixed(0)} '
        'vInst=${_instantVy.toStringAsFixed(0)} run=${run.dy.toStringAsFixed(1)}/${run.dx.toStringAsFixed(1)} '
        'straight=${_straightness.toStringAsFixed(2)} flips=${_flips.length} '
        'multi=$_multiTouch';
  }

  ArbitrationState _topTarget() {
    if (!_refreshing) return ArbitrationState.indicator;
    return _sheetEnabled ? ArbitrationState.sheet : ArbitrationState.list;
  }

  void _enter(ArbitrationState next, String reason) {
    _log('${state.name} -> ${next.name} ($reason) | ${describe()}');
    state = next;
  }

  double get _smoothedVy =>
      _tracker.getVelocityEstimate()?.pixelsPerSecond.dy ?? 0.0;

  double get _straightness =>
      _runPath == 0.0 ? 1.0 : (_last - _runStart).distance / _runPath;

  bool _dismissIntent() {
    // Armed, or tracked past the deadline, means committed to the indicator.
    final bool committed =
        _armed || _lastTime - _downTime > config.takeoverDeadline;
    if (!_sheetEnabled ||
        (committed && !config.refreshCanBecomeDismiss) ||
        _multiTouch ||
        _runDir <= 0) {
      return false;
    }
    final Offset run = _last - _runStart;
    final bool vertical =
        run.dy.abs() >= config.axisDominance * run.dx.abs() &&
        _straightness >= config.minStraightness;
    if (!vertical) return false;
    final double gate = _topBand
        ? config.dismissVelocityTop
        : config.dismissVelocityBody;
    return _lastTime - _downTime >= config.velocityHoldOff &&
        run.dy >= config.minRunForVelocity &&
        _flips.length < config.jitterFlips &&
        _smoothedVy >= gate &&
        _instantVy >= config.instantVelocityFactor * gate;
  }

  void _log(String message) => onLog?.call(message);
}
