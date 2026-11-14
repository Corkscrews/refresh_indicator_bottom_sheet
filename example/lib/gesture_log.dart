/// Every `[RSheet]` line, grouped per gesture, for the tuning overlay and the
/// experiments in docs/analysis/refresh-vs-dismiss-arbitration.md, section 7.
final GestureLog gestureLog = GestureLog();

/// Gestures from `begin:` to the next `begin:`, each with a tester label.
class GestureLog {
  final List<({List<String> lines, String? label})> gestures = [];
  String live = '';
  String transition = '';
  String release = '';

  void add(String message) {
    if (!message.startsWith('[RSheet] ')) return;
    final String line = message.substring(9);
    if (line.startsWith('begin:')) gestures.add((lines: [], label: null));
    if (gestures.isNotEmpty) gestures.last.lines.add(line);
    final int bar = line.indexOf(' | ');
    // Only describe() suffixes, which start with `t=`, are live state.
    if (bar >= 0 && line.startsWith('t=', bar + 3)) {
      live = line.substring(bar + 3);
    }
    if (line.contains(' -> ') && line.contains('(')) {
      transition = line.substring(0, bar < 0 ? line.length : bar);
    }
    if (line.startsWith('release:')) release = line;
  }

  void label(String label) {
    if (gestures.isEmpty) return;
    gestures.last = (lines: gestures.last.lines, label: label);
  }

  String export() => [
    for (final (i, g) in gestures.indexed)
      '## gesture ${i + 1} wanted=${g.label ?? '?'}\n${g.lines.join('\n')}',
  ].join('\n\n');
}
