import 'package:flutter/foundation.dart';

/// Prints every arbitration decision with the `[RSheet]` prefix. Debug aid.
bool debugRefreshSheetLogs = false;

/// Digits after the point for pixel values and px/s release velocities.
const int logPixelDigits = 1;

/// Digits after the point for the smoothed and instant velocities.
const int logSpeedDigits = 0;

/// Digits after the point for the straightness ratio.
const int logRatioDigits = 2;

/// Digits after the point for the sheet's fraction open.
const int logFractionDigits = 3;

/// Prints [message] with the `[RSheet]` prefix while [debugRefreshSheetLogs]
/// is set.
void refreshSheetLog(String message) {
  if (debugRefreshSheetLogs) debugPrint('[RSheet] $message');
}
