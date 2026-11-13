# refresh_indicator_bottom_sheet

`RefreshIndicatorOpt` is a wrapper around Flutter's `RefreshIndicator`.

```dart
RefreshIndicatorOpt(
  onRefresh: () async {},
  child: ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: const [ListTile(title: Text('Item'))],
  ),
)
```

The example app starts on a home screen and opens a bottom sheet with a pull-to-refresh list:

```sh
cd example
flutter run
```
