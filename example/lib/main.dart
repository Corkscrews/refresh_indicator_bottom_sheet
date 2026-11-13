import 'package:flutter/material.dart';
import 'package:refresh_indicator_bottom_sheet/refresh_indicator_bottom_sheet.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: HomeScreen());
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Refresh indicator')),
      body: Center(
        child: FilledButton(
          onPressed: () {
            showRefreshModalBottomSheet<void>(
              context: context,
              builder: (context) => const RefreshListSheet(),
            );
          },
          child: const Text('Open bottom sheet'),
        ),
      ),
    );
  }
}

class RefreshListSheet extends StatelessWidget {
  const RefreshListSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicatorOpt(
      onRefresh: () => Future<void>.delayed(const Duration(seconds: 1)),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: 30,
        itemBuilder: (context, index) {
          return ListTile(title: Text('Item ${index + 1}'));
        },
      ),
    );
  }
}
