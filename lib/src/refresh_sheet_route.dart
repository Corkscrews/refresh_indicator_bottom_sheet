import 'package:material_ui/material_ui.dart';

import 'debug_log.dart';

/// The stock modal sheet curve (`_kModalBottomSheetCurve`).
const Curve kSheetCurve = Easing.legacyDecelerate;

/// Finite-difference step for [_CurveSimulation.dx].
const double _kDerivativeStep = 1e-3;

/// A [ModalBottomSheetRoute] whose sheet a `RefreshIndicatorOpt` inside it can
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
  }) : _curve = sheetAnimationStyle?.curve ?? kSheetCurve,
       _reverseCurve = sheetAnimationStyle?.reverseCurve ?? kSheetCurve,
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

  /// The entry animation is still running.
  bool get entering => _entering;
  bool _entering = true;

  /// The route is popping; its controller must not be written (stock
  /// `_dismissUnderway`).
  bool get exiting => sheetController.status == AnimationStatus.reverse;

  @override
  TickerFuture didPush() =>
      // A drag that stops the entry early also ends it.
      super.didPush()..whenCompleteOrCancel(() => _entering = false);

  @override
  void didAdd() {
    super.didAdd();
    _entering = false;
  }

  @override
  Simulation? createSimulation({required bool forward}) {
    final double from = controller!.value;
    final double to = forward ? 1.0 : 0.0;
    refreshSheetLog(
      'route ${forward ? 'push' : 'pop'} animation '
      'from ${from.toStringAsFixed(logFractionDigits)}',
    );
    return _CurveSimulation(
      from: from,
      to: to,
      seconds: _secondsFor(
        forward ? transitionDuration : reverseTransitionDuration,
        (to - from).abs(),
      ),
      curve: forward ? _curve : _reverseCurve,
    );
  }
}

/// Like forward()/reverse(): only the remaining distance takes time.
double _secondsFor(Duration full, double distance) =>
    full.inMicroseconds / Duration.microsecondsPerSecond * distance;

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
  double dx(double time) =>
      (x(time + _kDerivativeStep) - x(time)) / _kDerivativeStep;

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
