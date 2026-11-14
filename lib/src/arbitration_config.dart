import 'package:flutter/foundation.dart';

// Starting points; tune with the experiments in
// docs/analysis/refresh-vs-dismiss-arbitration.md, section 7.
const double _kEdgeSlop = 1.0;
const double _kTopBandFraction = 0.33;
const double _kAxisDominance = 2.0;
const double _kMinStraightness = 0.85;
const double _kReversalHysteresis = 8.0;
const Duration _kVelocityHoldOff = Duration(milliseconds: 40);
const Duration _kTakeoverDeadline = Duration(milliseconds: 200);
const double _kMinRunForVelocity = 32.0;
const double _kDismissVelocityTop = 1100.0;
const double _kDismissVelocityBody = 800.0;
const double _kInstantVelocityFactor = 0.5;
const int _kJitterFlips = 2;
const double _kArmDistanceFraction = 0.25;
const double _kArmHysteresis = 12.0;
const double _kCloseVelocity = 700.0;
const double _kCloseProgress = 0.5;
const double _kIndicatorTravelFactor = 1.5;
const Duration _kSnapDuration = Duration(milliseconds: 150);
const Duration _kRetractDuration = Duration(milliseconds: 200);

/// Every threshold the pull-to-refresh / drag-to-dismiss arbitration uses.
///
/// `V` is the list viewport height and `H` the sheet height. Values marked as
/// hypotheses are starting points to be tuned by the experiments in
/// docs/analysis/refresh-vs-dismiss-arbitration.md, section 7.
@immutable
class RefreshSheetArbitrationConfig {
  const RefreshSheetArbitrationConfig({
    this.edgeSlop = _kEdgeSlop,
    this.topBandFraction = _kTopBandFraction,
    this.axisDominance = _kAxisDominance,
    this.minStraightness = _kMinStraightness,
    this.reversalHysteresis = _kReversalHysteresis,
    this.velocityHoldOff = _kVelocityHoldOff,
    this.takeoverDeadline = _kTakeoverDeadline,
    this.refreshCanBecomeDismiss = true,
    this.minRunForVelocity = _kMinRunForVelocity,
    this.dismissVelocityTop = _kDismissVelocityTop,
    this.dismissVelocityBody = _kDismissVelocityBody,
    this.instantVelocityFactor = _kInstantVelocityFactor,
    this.jitterFlips = _kJitterFlips,
    this.armDistanceFraction = _kArmDistanceFraction,
    this.armHysteresis = _kArmHysteresis,
    this.closeVelocity = _kCloseVelocity,
    this.closeProgress = _kCloseProgress,
    this.indicatorTravelFactor = _kIndicatorTravelFactor,
    this.snapDuration = _kSnapDuration,
    this.retractDuration = _kRetractDuration,
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

  /// When true (the default), a pull the indicator is tracking (armed or past
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
  /// pull then never hands over to the sheet.
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
