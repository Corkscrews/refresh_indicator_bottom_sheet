import 'dart:math' as math;

import 'package:flutter/gestures.dart';

// VelocityTracker's horizon (gestures/velocity_tracker.dart).
const Duration _kVelocityWindow = Duration(milliseconds: 100);

/// What the arbitrator needs to know about one pointer gesture: its smoothed
/// and instantaneous velocity, direction flips, and the run since the last
/// reversal. It only records samples; it makes no decisions.
class PointerHistory {
  // Pointer bookkeeping.
  int _pointers = 0;
  int? _primary;
  bool _multiTouch = false;
  Duration _downTime = Duration.zero;
  Offset _downLocal = Offset.zero;
  VelocityTracker _tracker = VelocityTracker.withKind(PointerDeviceKind.touch);

  // Latest sample.
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

  /// True once a second finger has landed, until every finger lifts.
  bool get multiTouch => _multiTouch;

  Duration get downTime => _downTime;
  Duration get lastTime => _lastTime;
  Offset get downLocal => _downLocal;

  /// Displacement from the start of the current run to the latest sample.
  Offset get run => _last - _runStart;

  /// Direction of the current run: +1 down, -1 up, 0 before it has moved.
  int get runDir => _runDir;

  int get flipCount => _flips.length;
  double get instantVy => _instantVy;

  /// Smoothed vertical velocity, px/s, positive down.
  double get smoothedVy =>
      _tracker.getVelocityEstimate()?.pixelsPerSecond.dy ?? 0.0;

  /// Net displacement over path length of the current run; 1.0 before any path.
  double get straightness => _runPath == 0.0 ? 1.0 : run.distance / _runPath;

  void down(
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

  void move(
    int pointer,
    Duration time,
    Offset position, {
    required double reversalHysteresis,
  }) {
    if (pointer != _primary) return;
    _tracker.addPosition(time, position);
    final Offset step = position - _last;
    final double dt =
        (time - _lastTime).inMicroseconds / Duration.microsecondsPerSecond;
    if (dt > 0) _instantVy = step.dy / dt;
    _trackFlips(time, step.dy);
    _trackRun(position, step, reversalHysteresis);
    _last = position;
    _lastTime = time;
  }

  void up(int pointer) {
    _pointers = math.max(0, _pointers - 1);
  }

  void _trackFlips(Duration time, double dy) {
    final int sign = dy.sign.toInt();
    if (sign != 0) {
      if (_lastStepSign != 0 && sign != _lastStepSign) _flips.add(time);
      _lastStepSign = sign;
    }
    _flips.removeWhere((flip) => time - flip > _kVelocityWindow);
  }

  void _trackRun(Offset position, Offset step, double reversalHysteresis) {
    if (_runDir == 0) {
      _runDir = (position.dy - _runStart.dy).sign.toInt();
      _runExtreme = position;
      _runPath += step.distance;
      return;
    }
    if ((position.dy - _runExtreme.dy) * _runDir >= 0) {
      _runExtreme = position;
      _runPath += step.distance;
      return;
    }
    if ((_runExtreme.dy - position.dy) * _runDir > reversalHysteresis) {
      _runStart = _runExtreme;
      _runExtreme = position;
      _runDir = -_runDir;
      _runPath = (position - _runStart).distance;
      return;
    }
    _runPath += step.distance;
  }
}
