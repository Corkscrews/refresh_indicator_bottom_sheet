import 'dart:async';
import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoActivityIndicator;
import 'package:material_ui/material_ui.dart';

import 'arbitration.dart';
import 'debug_log.dart';
import 'refresh_sheet_route.dart';
import 'sheet_scroll.dart';

export 'arbitration.dart' show RefreshSheetArbitrationConfig;
export 'debug_log.dart' show debugRefreshSheetLogs;
export 'refresh_sheet_route.dart'
    show RefreshSheetRoute, showRefreshModalBottomSheet;

const double _kIndicatorSize = 41.0; // RefreshProgressIndicator's size
const double _kDefaultDisplacement = 40.0;
const double _kDefaultElevation = 2.0;

/// Arc fill at a full arm pull. While refreshing, the spinner runs instead.
const double _kPullArcFraction = 0.75;

/// Drop-in wrapper around [RefreshIndicator].
///
/// Inside a [RefreshSheetRoute], one pointer is shared between the list, a
/// pull-to-refresh indicator and the sheet: a soft pull from the top refreshes,
/// a fast one drags the sheet, and reversing hands the pointer back.
/// See [RefreshSheetArbitrationConfig]. Everywhere else it is a plain
/// [RefreshIndicator]. On iOS the spinner is a [CupertinoActivityIndicator];
/// every other platform keeps the Material indicator. The indicator drawn
/// inside a [RefreshSheetRoute] follows the same split.
class RefreshIndicatorOpt extends StatefulWidget {
  const RefreshIndicatorOpt({
    super.key,
    this.displacement = _kDefaultDisplacement,
    this.edgeOffset = 0.0,
    required this.onRefresh,
    this.color,
    this.backgroundColor,
    this.notificationPredicate = defaultScrollNotificationPredicate,
    this.semanticsLabel,
    this.semanticsValue,
    this.strokeWidth = RefreshProgressIndicator.defaultStrokeWidth,
    this.triggerMode = RefreshIndicatorTriggerMode.onEdge,
    this.elevation = _kDefaultElevation,
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
    with SingleTickerProviderStateMixin
    implements SheetDragHost {
  late final SheetScrollController _controller = SheetScrollController(this);
  late final RefreshSheetArbitrator _arbitrator = RefreshSheetArbitrator(
    config: widget.arbitration,
    onLog: refreshSheetLog,
  );

  /// Indicator progress: 1.0 is a pull of one arm distance.
  late final AnimationController _indicator;
  RefreshSheetRoute<dynamic>? _route;
  bool _refreshing = false;

  @override
  RefreshSheetRoute<dynamic>? get route => _route;

  @override
  RefreshSheetArbitrator get arbitrator => _arbitrator;

  @override
  bool get refreshing => _refreshing;

  @override
  double sheetHeight() {
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
  @override
  void syncIndicator() {
    if (_refreshing) return;
    if (_arbitrator.state == ArbitrationState.indicator) {
      _indicator.value = _pullProgress();
    } else if (_indicator.value > 0.0 && !_indicator.isAnimating) {
      _indicator.animateTo(0.0, duration: widget.arbitration.snapDuration);
    }
  }

  @override
  void commit(ArbitrationCommit commit) {
    final route = _route!;
    switch (commit) {
      case ArbitrationCommit.list:
        break;
      case ArbitrationCommit.retract:
        _indicator.animateTo(0.0, duration: widget.arbitration.snapDuration);
      case ArbitrationCommit.refresh:
        unawaited(_refresh());
      case ArbitrationCommit.close || ArbitrationCommit.springBack
          when route.exiting:
        break; // a pop mid-drag owns the controller now
      case ArbitrationCommit.close when route.isCurrent:
        route.navigator!.pop();
      case ArbitrationCommit.close || ArbitrationCommit.springBack:
        route.sheetController.animateTo(1.0, curve: kSheetCurve);
    }
  }

  Future<void> _refresh() async {
    final config = widget.arbitration;
    setState(() => _refreshing = true);
    _indicator.animateTo(
      1.0 / config.indicatorTravelFactor,
      duration: config.snapDuration,
    );
    refreshSheetLog('onRefresh started');
    try {
      await widget.onRefresh();
    } finally {
      refreshSheetLog('onRefresh finished (mounted=$mounted)');
      if (mounted) {
        setState(() => _refreshing = false);
        _indicator.animateTo(0.0, duration: config.retractDuration);
      }
    }
  }

  double _pullProgress() {
    final double arm = _arbitrator.armDistance;
    return arm <= 0.0 ? 0.0 : math.min(_arbitrator.pull / arm, 1.0);
  }

  @override
  void initState() {
    super.initState();
    // Not lazy: creating a ticker inside dispose() asserts on Flutter 3.44.
    _indicator = AnimationController(vsync: this);
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
    refreshSheetLog(
      'build: route=${route.runtimeType} arbitrated=${_route != null} '
      'enableDrag=${_route?.enableDrag} platform=${Theme.of(context).platform}',
    );
    if (_route == null) return _buildPlain(context);
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: _buildArbitratedBody(),
    );
  }

  /// Outside a [RefreshSheetRoute] this is the stock indicator.
  Widget _buildPlain(BuildContext context) {
    // Adaptive is Cupertino on iOS and macOS; this package only switches iOS.
    final stock = Theme.of(context).platform == TargetPlatform.iOS
        ? RefreshIndicator.adaptive
        : RefreshIndicator.new;
    return stock(
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

  Widget _buildArbitratedBody() => Stack(
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
  );

  void _onPointerDown(PointerDownEvent e) {
    refreshSheetLog(
      'pointer down #${e.pointer} kind=${e.kind} at=${e.localPosition}',
    );
    _arbitrator.pointerDown(
      e.pointer,
      e.timeStamp,
      e.position,
      e.localPosition,
      e.kind,
    );
  }

  void _onPointerMove(PointerMoveEvent e) =>
      _arbitrator.pointerMove(e.pointer, e.timeStamp, e.position);

  void _onPointerUp(PointerUpEvent e) {
    refreshSheetLog('pointer up #${e.pointer}');
    _arbitrator.pointerUp(e.pointer);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    refreshSheetLog('pointer cancel #${e.pointer}');
    _arbitrator.pointerCancel(e.pointer);
  }

  Widget _buildIndicator(BuildContext context, Widget? _) {
    final double progress = _indicator.value;
    if (progress == 0.0 && !_refreshing) return const SizedBox.shrink();
    return Transform.translate(
      offset: Offset(0.0, _indicatorTravel(progress)),
      child: Align(
        alignment: Alignment.topCenter,
        child: Opacity(
          opacity: _refreshing ? 1.0 : progress,
          child: _spinner(context, progress),
        ),
      ),
    );
  }

  /// Same geometry as the stock indicator: at progress 1/travelFactor it rests
  /// at `displacement`.
  double _indicatorTravel(double progress) =>
      progress *
          widget.arbitration.indicatorTravelFactor *
          (widget.displacement + _kIndicatorSize) -
      _kIndicatorSize;

  /// iOS grows ticks while pulling, then spins. Other platforms keep the
  /// Material ring. A spinning [CupertinoActivityIndicator] never settles, so
  /// it is only built while [onRefresh] is running.
  Widget _spinner(BuildContext context, double progress) {
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return _refreshing
          ? CupertinoActivityIndicator(color: widget.color)
          : CupertinoActivityIndicator.partiallyRevealed(
              color: widget.color,
              progress: progress,
            );
    }
    return RefreshProgressIndicator(
      value: _refreshing ? null : _kPullArcFraction * progress,
      color: widget.color,
      backgroundColor: widget.backgroundColor,
      strokeWidth: widget.strokeWidth,
      elevation: widget.elevation,
      semanticsLabel:
          widget.semanticsLabel ??
          MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
      semanticsValue: widget.semanticsValue,
    );
  }
}
