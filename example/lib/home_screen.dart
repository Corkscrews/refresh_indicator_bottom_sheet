import 'package:material_ui/material_ui.dart';
import 'package:refresh_indicator_bottom_sheet/refresh_indicator_bottom_sheet.dart';
import 'package:refresh_indicator_bottom_sheet_example/refresh_list_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _Physics { system, android, ios }

class _HomeScreenState extends State<HomeScreen> {
  var _config = const RefreshSheetArbitrationConfig();
  var _scrollControlled = false;
  var _fewRows = false;
  var _dragHandle = false;
  var _enableDrag = true;
  var _physics = _Physics.system;

  void _open() {
    showRefreshModalBottomSheet<void>(
      context: context,
      isScrollControlled: _scrollControlled,
      showDragHandle: _dragHandle,
      enableDrag: _enableDrag,
      builder: (context) {
        final Widget sheet = RefreshListSheet(
          config: _config,
          itemCount: _fewRows ? 3 : 30,
        );
        if (_physics == _Physics.system) return sheet;
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            physics: _physics == _Physics.ios
                ? const BouncingScrollPhysics()
                : const ClampingScrollPhysics(),
          ),
          child: sheet,
        );
      },
    );
  }

  // Rebuilds the immutable config with one field changed.
  RefreshSheetArbitrationConfig _with({
    double? topBandFraction,
    Duration? takeoverDeadline,
    bool? refreshCanBecomeDismiss,
    double? dismissVelocityTop,
    double? dismissVelocityBody,
    double? armDistanceFraction,
    double? closeProgress,
  }) {
    final c = _config;
    return RefreshSheetArbitrationConfig(
      edgeSlop: c.edgeSlop,
      topBandFraction: topBandFraction ?? c.topBandFraction,
      axisDominance: c.axisDominance,
      minStraightness: c.minStraightness,
      reversalHysteresis: c.reversalHysteresis,
      velocityHoldOff: c.velocityHoldOff,
      takeoverDeadline: takeoverDeadline ?? c.takeoverDeadline,
      refreshCanBecomeDismiss:
          refreshCanBecomeDismiss ?? c.refreshCanBecomeDismiss,
      minRunForVelocity: c.minRunForVelocity,
      dismissVelocityTop: dismissVelocityTop ?? c.dismissVelocityTop,
      dismissVelocityBody: dismissVelocityBody ?? c.dismissVelocityBody,
      instantVelocityFactor: c.instantVelocityFactor,
      jitterFlips: c.jitterFlips,
      armDistanceFraction: armDistanceFraction ?? c.armDistanceFraction,
      armHysteresis: c.armHysteresis,
      closeVelocity: c.closeVelocity,
      closeProgress: closeProgress ?? c.closeProgress,
      indicatorTravelFactor: c.indicatorTravelFactor,
      snapDuration: c.snapDuration,
      retractDuration: c.retractDuration,
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    String Function(double) format,
    RefreshSheetArbitrationConfig Function(double) apply,
  ) {
    return ListTile(
      title: Text('$label: ${format(value)}'),
      subtitle: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: (v) => setState(() => _config = apply(v)),
      ),
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(label),
      value: value,
      onChanged: (v) => setState(() => onChanged(v)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _config;
    String px(double v) => '${v.round()} px/s';
    String pct(double v) => '${(v * 100).round()}%';
    return Scaffold(
      appBar: AppBar(title: const Text('Refresh indicator')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _open,
        label: const Text('Open bottom sheet'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 96, bottom: 96),
        children: <Widget>[
          const ListTile(title: Text('Sheet')),
          _switch(
            'Full height (isScrollControlled)',
            _scrollControlled,
            (v) => _scrollControlled = v,
          ),
          _switch('3 rows instead of 30', _fewRows, (v) => _fewRows = v),
          _switch('Drag handle', _dragHandle, (v) => _dragHandle = v),
          _switch('enableDrag', _enableDrag, (v) => _enableDrag = v),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<_Physics>(
              segments: const <ButtonSegment<_Physics>>[
                ButtonSegment(value: _Physics.system, label: Text('System')),
                ButtonSegment(value: _Physics.android, label: Text('Clamping')),
                ButtonSegment(value: _Physics.ios, label: Text('Bouncing')),
              ],
              selected: <_Physics>{_physics},
              onSelectionChanged: (s) => setState(() => _physics = s.first),
            ),
          ),
          const ListTile(title: Text('Arbitration')),
          _switch(
            'refreshCanBecomeDismiss',
            c.refreshCanBecomeDismiss,
            (v) => _config = _with(refreshCanBecomeDismiss: v),
          ),
          _slider(
            'takeoverDeadline',
            c.takeoverDeadline.inMilliseconds.toDouble(),
            50,
            600,
            (v) => '${v.round()} ms',
            (v) => _with(takeoverDeadline: Duration(milliseconds: v.round())),
          ),
          _slider(
            'dismissVelocityTop',
            c.dismissVelocityTop,
            400,
            3000,
            px,
            (v) => _with(dismissVelocityTop: v),
          ),
          _slider(
            'dismissVelocityBody',
            c.dismissVelocityBody,
            400,
            3000,
            px,
            (v) => _with(dismissVelocityBody: v),
          ),
          _slider(
            'topBandFraction',
            c.topBandFraction,
            0.1,
            0.9,
            pct,
            (v) => _with(topBandFraction: v),
          ),
          _slider(
            'armDistanceFraction',
            c.armDistanceFraction,
            0.1,
            0.5,
            pct,
            (v) => _with(armDistanceFraction: v),
          ),
          _slider(
            'closeProgress',
            c.closeProgress,
            0.2,
            0.8,
            pct,
            (v) => _with(closeProgress: v),
          ),
          Center(
            child: TextButton(
              onPressed: () => setState(
                () => _config = const RefreshSheetArbitrationConfig(),
              ),
              child: const Text('Reset to defaults'),
            ),
          ),
        ],
      ),
    );
  }
}
