import 'package:material_ui/material_ui.dart';
import 'package:refresh_indicator_bottom_sheet/refresh_indicator_bottom_sheet.dart';

class RefreshListSheet extends StatelessWidget {
  const RefreshListSheet({
    super.key,
    this.config = const RefreshSheetArbitrationConfig(),
    this.itemCount = 30,
  });

  final RefreshSheetArbitrationConfig config;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicatorOpt(
      arbitration: config,
      // Long enough to try a pull while the refresh runs (matrix row 9).
      onRefresh: () => Future<void>.delayed(const Duration(seconds: 2)),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          return ListTile(title: Text('Item ${index + 1}'));
        },
      ),
    );
  }
}
