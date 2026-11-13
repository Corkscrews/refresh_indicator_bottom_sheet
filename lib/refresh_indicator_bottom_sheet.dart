import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'src/arbitration.dart';

export 'src/arbitration.dart' show RefreshSheetArbitrationConfig;

const Curve _kSheetCurve =
    Easing.legacyDecelerate; // stock _kModalBottomSheetCurve
const double _kIndicatorSize = 41.0; // RefreshProgressIndicator's size

/// Prints every arbitration decision with the `[RSheet]` prefix. Debug aid.
bool debugRefreshSheetLogs = true;

void _log(String message) {
  if (debugRefreshSheetLogs) debugPrint('[RSheet] $message');
}

String _f(double v) => v.toStringAsFixed(1);

/// Drop-in wrapper around [RefreshIndicator].
///
/// Inside a [RefreshSheetRoute], one pointer is shared between the list, a
/// pull-to-refresh indicator and the sheet: a soft pull from the top refreshes,
/// a fast or long one drags the sheet, and reversing hands the pointer back.
/// See [RefreshSheetArbitrationConfig]. Everywhere else it is a plain
/// [RefreshIndicator].
class RefreshIndicatorOpt extends StatefulWidget {
  const RefreshIndicatorOpt({
    super.key,
    this.displacement = 40.0,
    this.edgeOffset = 0.0,
    required this.onRefresh,
    this.color,
    this.backgroundColor,
    this.notificationPredicate = defaultScrollNotificationPredicate,
    this.semanticsLabel,
    this.semanticsValue,
    this.strokeWidth = RefreshProgressIndicator.defaultStrokeWidth,
    this.triggerMode = RefreshIndicatorTriggerMode.onEdge,
    this.elevation = 2.0,
    this.arbitration = const RefreshSheetArbitrationConfig(),
    required this.child,
  });

  final double displacement;
  final double edgeOffset;
  final RefreshCallback onRefresh;
  final Color? color;
  final Color? backgroundColor;

  /// shortcut: ignored inside a [RefreshSheetRoute], where the inherited
  /// scroll controller decides which list is arbitrated; plan open question 7.
  final ScrollNotificationPredicate notificationPredicate;
  final String? semanticsLabel;
  final String? semanticsValue;
  final double strokeWidth;

  /// shortcut: inside a [RefreshSheetRoute] only `onEdge` is implemented;
  /// plan open question 5.
  final RefreshIndicatorTriggerMode triggerMode;
  final double elevation;

  /// Thresholds for sharing a pull between refresh and the sheet. Only used
  /// inside a [RefreshSheetRoute].
  final RefreshSheetArbitrationConfig arbitration;
  final Widget child;

  @override
  State<RefreshIndicatorOpt> createState() => _RefreshIndicatorOptState();
}

class _RefreshIndicatorOptState extends State<RefreshIndicatorOpt>
    with SingleTickerProviderStateMixin {
  late final _SheetScrollController _controller = _SheetScrollController(this);
  late final RefreshSheetArbitrator _arbitrator = RefreshSheetArbitrator(
    config: widget.arbitration,
    onLog: _log,
  );

  /// Indicator progress: 1.0 is a pull of one arm distance.
  late final AnimationController _indicator = AnimationController(vsync: this);
  RefreshSheetRoute<dynamic>? _route;
  bool _refreshing = false;

  /// Height of the enclosing [BottomSheet], or 0 if there is none.
  double _sheetHeight() {
    var height = 0.0;
    context.visitAncestorElements((element) {
      if (element.widget is! BottomSheet) return true;
      final box = element.findRenderObject();
      if (box is RenderBox && box.hasSize) height = box.size.height;
      return false;
    });
    return height;
  }

  /// Mirrors the arbitrator's pull on screen while the finger is down.
  void _syncIndicator() {
    if (_refreshing) return;
    if (_arbitrator.state == ArbitrationState.indicator) {
      final double arm = _arbitrator.armDistance;
      _indicator.value = arm <= 0.0
          ? 0.0
          : math.min(_arbitrator.pull / arm, 1.0);
    } else if (_indicator.value > 0.0 && !_indicator.isAnimating) {
      _indicator.animateTo(0.0, duration: widget.arbitration.snapDuration);
    }
  }

  void _commit(ArbitrationCommit commit) {
    final route = _route!;
    switch (commit) {
      case ArbitrationCommit.list:
        break;
      case ArbitrationCommit.retract:
        _indicator.animateTo(0.0, duration: widget.arbitration.snapDuration);
      case ArbitrationCommit.refresh:
        unawaited(_refresh());
      case ArbitrationCommit.close:
        if (route.isCurrent) route.navigator!.pop();
      case ArbitrationCommit.springBack:
        route.sheetController.animateTo(1.0, curve: _kSheetCurve);
    }
  }

  Future<void> _refresh() async {
    final config = widget.arbitration;
    setState(() => _refreshing = true);
    _indicator.animateTo(
      1.0 / config.indicatorTravelFactor,
      duration: config.snapDuration,
    );
    _log('onRefresh started');
    try {
      await widget.onRefresh();
    } finally {
      _log('onRefresh finished (mounted=$mounted)');
      if (mounted) {
        setState(() => _refreshing = false);
        _indicator.animateTo(0.0, duration: config.retractDuration);
      }
    }
  }

  @override
  void didUpdateWidget(RefreshIndicatorOpt oldWidget) {
    super.didUpdateWidget(oldWidget);
    _arbitrator.config = widget.arbitration;
  }

  @override
  void dispose() {
    _indicator.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    _route = route is RefreshSheetRoute ? route : null;
    _log(
      'build: route=${route.runtimeType} arbitrated=${_route != null} '
      'enableDrag=${_route?.enableDrag} platform=${Theme.of(context).platform}',
    );
    if (_route == null) {
      return RefreshIndicator(
        displacement: widget.displacement,
        edgeOffset: widget.edgeOffset,
        onRefresh: widget.onRefresh,
        color: widget.color,
        backgroundColor: widget.backgroundColor,
        notificationPredicate: widget.notificationPredicate,
        semanticsLabel: widget.semanticsLabel,
        semanticsValue: widget.semanticsValue,
        strokeWidth: widget.strokeWidth,
        triggerMode: widget.triggerMode,
        elevation: widget.elevation,
        child: widget.child,
      );
    }
    return Listener(
      onPointerDown: (e) {
        _log('pointer down #${e.pointer} kind=${e.kind} at=${e.localPosition}');
        _arbitrator.pointerDown(
          e.pointer,
          e.timeStamp,
          e.position,
          e.localPosition,
          e.kind,
        );
      },
      onPointerMove: (e) =>
          _arbitrator.pointerMove(e.pointer, e.timeStamp, e.position),
      onPointerUp: (e) {
        _log('pointer up #${e.pointer}');
        _arbitrator.pointerUp(e.pointer);
      },
      onPointerCancel: (e) {
        _log('pointer cancel #${e.pointer}');
        _arbitrator.pointerUp(e.pointer);
      },
      child: Stack(
        children: <Widget>[
          PrimaryScrollController(
            controller: _controller,
            automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
            child: widget.child,
          ),
          Positioned.fill(
            top: widget.edgeOffset,
            // The indicator slides in from above the list; never paint it over
            // the sheet's top edge (the stock one clips via SizeTransition).
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _indicator,
                builder: _buildIndicator,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicator(BuildContext context, Widget? _) {
    final double progress = _indicator.value;
    if (progress == 0.0 && !_refreshing) return const SizedBox.shrink();
    // Same geometry as the stock indicator: at progress 1/travelFactor it
    // rests at `displacement`.
    final double travel =
        progress *
            widget.arbitration.indicatorTravelFactor *
            (widget.displacement + _kIndicatorSize) -
        _kIndicatorSize;
    return Transform.translate(
      offset: Offset(0.0, travel),
      child: Align(
        alignment: Alignment.topCenter,
        child: Opacity(
          opacity: _refreshing ? 1.0 : progress,
          child: RefreshProgressIndicator(
            value: _refreshing ? null : 0.75 * progress,
            color: widget.color,
            backgroundColor: widget.backgroundColor,
            strokeWidth: widget.strokeWidth,
            elevation: widget.elevation,
            semanticsLabel:
                widget.semanticsLabel ??
                MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
            semanticsValue: widget.semanticsValue,
          ),
        ),
      ),
    );
  }
}

class _SheetScrollController extends ScrollController {
  _SheetScrollController(this.host);

  final _RefreshIndicatorOptState host;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    _log(
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

  final _RefreshIndicatorOptState host;

  bool _restAtDown = true;
  bool _active = false;
  bool _cancelled = false;
  double _sheetHeight = 0.0;
  double _written = 0.0; // last sheet offset applied to the route controller

  @override
  ScrollHoldController hold(VoidCallback holdCancelCallback) {
    // A finger that catches a moving or bouncing list only stops it.
    _restAtDown = !(activity?.isScrolling ?? false);
    _log(
      'hold: activity=${activity.runtimeType} restAtDown=$_restAtDown pixels=${_f(pixels)}',
    );
    return super.hold(holdCancelCallback);
  }

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    final route = host._route;
    final Drag drag = super.drag(details, dragCancelCallback);
    if (route == null) return drag;
    final arbitrator = host._arbitrator;
    final sheet = route.sheetController;
    _sheetHeight = host._sheetHeight();
    final bool eligible =
        route.isCurrent &&
        _restAtDown &&
        details.kind != PointerDeviceKind.trackpad &&
        pixels <= minScrollExtent + arbitrator.config.edgeSlop;
    _log(
      'drag start: eligible=$eligible | isCurrent=${route.isCurrent} '
      'restAtDown=$_restAtDown kind=${details.kind} pixels=${_f(pixels)} '
      'min=${_f(minScrollExtent)} enableDrag=${route.enableDrag} '
      'sheetValue=${sheet.value.toStringAsFixed(3)}',
    );
    arbitrator.beginDrag(
      eligible: eligible,
      refreshing: host._refreshing,
      sheetEnabled: route.enableDrag && route.isCurrent,
      viewport: viewportDimension,
      sheetHeight: _sheetHeight,
      sheetOffset: (1.0 - sheet.value) * _sheetHeight,
    );
    _written = arbitrator.sheetOffset;
    _restAtDown = true;
    _cancelled = false;
    _active = true;
    return _CancelAwareDrag(drag, () => _cancelled = true);
  }

  @override
  void applyUserOffset(double delta) {
    if (!_active) {
      super.applyUserOffset(delta);
      return;
    }
    final arbitrator = host._arbitrator;
    final double toList = arbitrator.route(
      delta,
      room: pixels - minScrollExtent,
    );
    if (arbitrator.sheetOffset != _written) {
      // Stock _handleDragUpdate formula, in pixels owned by the sheet.
      host._route!.sheetController.value =
          1.0 - arbitrator.sheetOffset / _sheetHeight;
      _written = arbitrator.sheetOffset;
    }
    host._syncIndicator();
    if (toList != 0.0) super.applyUserOffset(toList);
    _log('delta ${_f(delta)} -> list ${_f(toList)} | ${arbitrator.describe()}');
  }

  @override
  void goBallistic(double velocity) {
    if (!_active) {
      super.goBallistic(velocity);
      return;
    }
    _active = false;
    // ScrollDragController.end negates the finger velocity.
    final ArbitrationCommit commit = host._arbitrator.release(
      -velocity,
      cancelled: _cancelled,
    );
    host._commit(commit);
    // Only the list's own release flings the list.
    super.goBallistic(commit == ArbitrationCommit.list ? velocity : 0.0);
  }
}

/// Lets the position tell a pointer cancel (never closes) from a release.
class _CancelAwareDrag implements Drag {
  _CancelAwareDrag(this._inner, this._onCancel);

  final Drag _inner;
  final VoidCallback _onCancel;

  @override
  void update(DragUpdateDetails details) => _inner.update(details);

  @override
  void end(DragEndDetails details) => _inner.end(details);

  @override
  void cancel() {
    _onCancel();
    _inner.cancel();
  }
}

/// A [ModalBottomSheetRoute] whose sheet a [RefreshIndicatorOpt] inside it can
/// drag from the list.
///
/// The stock sheet's drag handlers are private and only its own recognizer
/// feeds them, so the package moves the route's animation controller instead.
/// That controller is `@protected` on [TransitionRoute]; this subclass exposes
/// it. Sheet position is kept linear in the controller value (so the sheet
/// follows the finger one to one) and the entry and exit keep their easing
/// through [createSimulation].
class RefreshSheetRoute<T> extends ModalBottomSheetRoute<T> {
  RefreshSheetRoute({
    required super.builder,
    super.capturedThemes,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.backgroundColor,
    super.elevation,
    super.shape,
    super.clipBehavior,
    super.constraints,
    super.modalBarrierColor,
    super.isDismissible,
    super.enableDrag,
    super.showDragHandle,
    super.isScrollControlled = false,
    super.scrollControlDisabledMaxHeightRatio,
    super.settings,
    super.requestFocus,
    super.anchorPoint,
    super.useSafeArea,
    AnimationStyle? sheetAnimationStyle,
  }) : _curve = sheetAnimationStyle?.curve ?? _kSheetCurve,
       _reverseCurve = sheetAnimationStyle?.reverseCurve ?? _kSheetCurve,
       super(
         sheetAnimationStyle: AnimationStyle(
           curve: Curves.linear,
           reverseCurve: Curves.linear,
           duration: sheetAnimationStyle?.duration,
           reverseDuration: sheetAnimationStyle?.reverseDuration,
         ),
       );

  final Curve _curve;
  final Curve _reverseCurve;

  /// The route's own transition controller. 1.0 is fully open, 0.0 closed.
  AnimationController get sheetController => controller!;

  @override
  Simulation? createSimulation({required bool forward}) {
    final double from = controller!.value;
    final double to = forward ? 1.0 : 0.0;
    final Duration full = forward
        ? transitionDuration
        : reverseTransitionDuration;
    _log(
      'route ${forward ? 'push' : 'pop'} animation from ${from.toStringAsFixed(3)}',
    );
    return _CurveSimulation(
      from: from,
      to: to,
      // Like forward()/reverse(): only the remaining distance takes time.
      seconds:
          full.inMicroseconds /
          Duration.microsecondsPerSecond *
          (to - from).abs(),
      curve: forward ? _curve : _reverseCurve,
    );
  }
}

class _CurveSimulation extends Simulation {
  _CurveSimulation({
    required this.from,
    required this.to,
    required this.seconds,
    required this.curve,
  });

  final double from;
  final double to;
  final double seconds;
  final Curve curve;

  @override
  double x(double time) {
    if (seconds <= 0.0) return to;
    return from +
        (to - from) * curve.transform((time / seconds).clamp(0.0, 1.0));
  }

  @override
  double dx(double time) => (x(time + 1e-3) - x(time)) / 1e-3;

  @override
  bool isDone(double time) => time >= seconds;
}

/// Shows [builder] in a [RefreshSheetRoute], with the same defaults and
/// accessibility labels as [showModalBottomSheet].
Future<T?> showRefreshModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useRootNavigator = false,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final localizations = MaterialLocalizations.of(context);
  return navigator.push(
    RefreshSheetRoute<T>(
      builder: builder,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      isScrollControlled: isScrollControlled,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
    ),
  );
}
