# refresh_indicator_bottom_sheet

**A proof of concept. An attempt to fix a Flutter problem that has been open for years.**

Put a scrollable list in a modal bottom sheet. Add pull-to-refresh. Now try to swipe the sheet down to dismiss it.

You can't. Or you can refresh but not dismiss, or dismiss but not refresh. Nobody gets both. This package is my attempt to make the same downward pull do both, and to make it feel right.

## Demo

A slow pull from the top refreshes. A fast pull dismisses the sheet. Reversing mid-gesture hands the finger back.

https://github.com/user-attachments/assets/6bb81126-f2f4-4132-8426-94fd5eec69a5

## Why this exists

I keep running into this. Every few months I build a screen with a bottom sheet and a list, someone asks for pull-to-refresh, someone else asks that the sheet still closes with a swipe, and the answer is always some version of "pick one".

It isn't a bug in any single widget. It is two widgets, both correct, wanting the same finger.

A modal bottom sheet listens for a vertical drag. A `ListView` inside it also listens for a vertical drag. Both register a `VerticalDragGestureRecognizer` with the same slop. When the finger crosses that slop, the list is deeper in the tree, registers first, and wins the gesture arena. The arena result is final for that pointer. The sheet loses and never hears from the finger again.

So the sheet only moves if the finger lands somewhere that doesn't scroll. In a sheet that is all list, there is no such place.

Pull-to-refresh makes it worse. `RefreshIndicator` wants exactly the gesture the sheet wants: a downward pull from the top of the list. And once a stock `RefreshIndicator` has armed, nothing outside it can cancel it. If you want a pull to turn into a dismiss halfway, you can't write that on top of the stock widgets.

The workarounds on offer:

- Use `DraggableScrollableSheet`. That was the official answer in [#36283](https://github.com/flutter/flutter/issues/36283), but it is a different widget with a different model, and it has its own bugs: [#31739](https://github.com/flutter/flutter/issues/31739) (stuck, and a sheet pinned at full height only ever dismisses), [#116427](https://github.com/flutter/flutter/issues/116427) (a fast flick snaps the sheet and stops the list) and [#95673](https://github.com/flutter/flutter/issues/95673) (`enableDrag: false` ignored). See the table below.
- Listen for an `OverscrollNotification` and call `Navigator.pop` when it passes a threshold. The sheet never follows the finger. The author calls it "a patch, not an actual solution". On iOS it needs `ClampingScrollPhysics`, so bounce goes.
- Add a drag handle as a second affordance. That moves the problem. It doesn't solve it.
- Make the list too short to scroll. Then it isn't a list, and refresh is gone.

## What has been reported

None of this is new. Here is what I found, and why none of it is the fix. The long version is in [docs/analysis/refresh-vs-dismiss-arbitration.md](docs/analysis/refresh-vs-dismiss-arbitration.md).

| Report | What it says | Why it isn't the answer |
|---|---|---|
| [flutter/flutter#36283](https://github.com/flutter/flutter/issues/36283) "Can't swipe to dismiss scrollable Bottom Sheet" (open, P2) | The canonical report, opened in 2019. The official answer was `DraggableScrollableSheet`. A 2024 `NotificationListener` workaround pops on overscroll. In 2025 someone noted that Material 3's swipe-down guideline is "not possible in Flutter when we have a sheet with scrolling content". | Still open. The workaround pops on a threshold. The sheet never tracks the finger. |
| [flutter/flutter#24489](https://github.com/flutter/flutter/issues/24489) "ScrollPhysics do not trigger pull down dismiss event of bottomsheet" (closed as duplicate of #36283) | A list too short to scroll lets the sheet dismiss. A list that scrolls does not. | That is the gesture arena at work. It only works when there is no competing scrollable, so no pull-to-refresh. |
| [flutter/flutter#31739](https://github.com/flutter/flutter/issues/31739) "DraggableScrollableSheet gets stuck and won't move" | A follow-up describes a sheet pinned at full height that "only ever dismisses it when you interact". | A sheet pinned at full extent turns every downward drag into a dismiss. There is no room left for refresh. |
| [flutter/flutter#161687](https://github.com/flutter/flutter/issues/161687) "Cupertino Sheet should have drag to dismiss and nested scrolling work together" (fixed by PR #177337, January 2026) | One drag goes entirely to the scroll view or entirely to the sheet, and "we can't switch back and forth". | The fix is real and useful. It is Cupertino-only, it has two targets, and it has no refresh indicator. I reuse its seam (a `ScrollController` whose position overrides `applyUserOffset` and `goBallistic`), not its policy. |
| [flutter/flutter#116427](https://github.com/flutter/flutter/issues/116427) (closed as duplicate) | A fast flick on a `DraggableScrollableSheet` inside `showModalBottomSheet` snaps the sheet and stops the inner list scrolling. | When extent and list share one position, the app has no say in when a flick becomes a dismiss. |
| [flutter/flutter#95673](https://github.com/flutter/flutter/issues/95673) and [#127236](https://github.com/flutter/flutter/issues/127236) | `enableDrag: false` is ignored once a `DraggableScrollableSheet` is the child. A `shouldCloseOnMinExtent` flag was added. | The close is a binary event at min extent. It says nothing while the finger moves. |
| [Stack Overflow 57835416](https://stackoverflow.com/questions/57835416) | Dragging the list only scrolls it. The sheet moves only from a non-scrolling handle. | Same arena result. A handle is a second affordance, not an answer for the list area. |
| [jamesblasco/modal_bottom_sheet#135](https://github.com/jamesblasco/modal_bottom_sheet/issues/135) and [#47](https://github.com/jamesblasco/modal_bottom_sheet/issues/47) | With real scroll extent, a downward drag shows the Android overscroll glow but doesn't move the sheet. iOS bounce and dismiss collide. One comment says "it seems not possible to work around the issue". | A replacement route and sheet stack, with no refresh arbitration. I took two ideas from it: own the scroll controller, and split the top edge by where the gesture started. |

I did not find a single report, issue or package that arbitrates **list, refresh indicator and sheet** from one finger. That is the gap this package tries to fill.

## What it does

One pointer, three possible owners: the list, the refresh indicator, or the sheet. The package decides which one has it on every pointer move.

- **Soft pull from the top:** the refresh indicator takes it. Pull far enough, let go, `onRefresh` runs.
- **Fast pull from the top:** the sheet takes it, tracks your finger one to one, and closes or springs back on release.
- **Reverse mid-gesture:** the finger hands back to the previous owner without lifting. Upward movement unwinds the sheet, then the indicator, then scrolls the list.
- **Anywhere else:** the list scrolls as it always did, with the platform's own physics.

The decision is a pure-Dart arbitrator ([lib/src/arbitration.dart](lib/src/arbitration.dart)) that looks at direction, straightness, velocity, how long ago the finger landed and whether the indicator is armed. Every threshold lives in one config object, `RefreshSheetArbitrationConfig`.

How it works, without a custom sheet widget and without copying framework code:

- A package-owned `ScrollController` diverts drag deltas before they reach the list.
- A three-line `ModalBottomSheetRoute` subclass exposes the route's own animation controller, so the sheet moves with the same formula the stock sheet uses.
- Inside that route, `RefreshIndicatorOpt` runs its own indicator state, because a stock `RefreshIndicator` can't be cancelled once it arms. Outside the route it is a plain `RefreshIndicator`.

On iOS the spinner is a `CupertinoActivityIndicator`. Everywhere else it is the Material indicator.

## How to use it

It isn't on pub.dev. It is a PoC, so use a git dependency:

```yaml
dependencies:
  refresh_indicator_bottom_sheet:
    git: https://github.com/Corkscrews/refresh_indicator_bottom_sheet.git
```

Open the sheet with `showRefreshModalBottomSheet` and put a `RefreshIndicatorOpt` around your list:

```dart
import 'package:material_ui/material_ui.dart';
import 'package:refresh_indicator_bottom_sheet/refresh_indicator_bottom_sheet.dart';

showRefreshModalBottomSheet<void>(
  context: context,
  builder: (context) => RefreshIndicatorOpt(
    onRefresh: () async {
      // reload your data
    },
    child: ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: 30,
      itemBuilder: (context, i) => ListTile(title: Text('Item ${i + 1}')),
    ),
  ),
);
```

Two rules:

- Don't pass your own `controller` to the list. The package arbitrates the list that uses the inherited `PrimaryScrollController`. A list with its own controller is left alone.
- Keep `AlwaysScrollableScrollPhysics` on the list, so a short list still takes the pull.

To tune the feel, pass a config:

```dart
RefreshIndicatorOpt(
  arbitration: const RefreshSheetArbitrationConfig(
    refreshCanBecomeDismiss: false, // a tracked pull stays a refresh
    dismissVelocityTop: 1400,       // px/s needed to hand the pull to the sheet
  ),
  onRefresh: onRefresh,
  child: list,
)
```

Outside a `RefreshSheetRoute`, `RefreshIndicatorOpt` behaves like `RefreshIndicator` and the config is ignored.

### Try it

```sh
cd example
fvm flutter run
```

The example has a tuning screen: sheet variants, a platform physics override, sliders for the thresholds, a live overlay of the arbitrator state, and per-gesture logs you can copy out. That is how I have been tuning it, on a device.

### Requirements

- Flutter 3.44 or newer (Dart 3.12). That is the floor set by `material_ui` and `cupertino_ui`.
- Development runs on Flutter 3.50.0, pinned in [.fvmrc](.fvmrc). Use `fvm flutter` and you get that version.
- The lowest versions have been checked: `flutter pub downgrade` on Flutter 3.44.5 passes `flutter analyze` and all tests. I haven't run 3.44.0 itself.

## Where it is, honestly

This is a PoC. It works on my devices. It is not a finished product.

- The thresholds are starting points. The experiments in section 7 of the analysis doc haven't all been run. Expect to tune them.
- Only `RefreshIndicatorTriggerMode.onEdge` is implemented inside the route.
- `notificationPredicate` is ignored inside the route. One vertical scrollable at depth 0 is assumed.
- Touch and stylus only. Mouse drags, mouse wheel and trackpad scroll the list.
- A drag that starts mid-list and reaches the top with the finger still down stays a list scroll. It does not turn into a sheet drag.
- A slow pull can't dismiss the sheet. By design, a slow pull is a refresh. Use the scrim, system back or a drag handle to close it slowly.
- With `refreshCanBecomeDismiss` on (the default), a fast lift-off flick after the indicator arms can close the sheet. Turn it off if that bites you.
- It doesn't use `PopScope` yet. A refused pop isn't handled.
- API names and defaults will change.

The full open questions are in [docs/analysis/refresh-vs-dismiss-arbitration.md](docs/analysis/refresh-vs-dismiss-arbitration.md), section 8.

## Contributing

Issues and PRs are welcome. This is a PoC, so the most useful contribution is usually a gesture that feels wrong.

1. Fork the repo and clone it. Use [FVM](https://fvm.app): `.fvmrc` pins Flutter 3.50.0, and `fvm flutter` picks it up.
2. Run `fvm flutter pub get`, then `fvm flutter analyze` and `fvm flutter test`. Both must pass before you change anything.
3. Run the example on a real device: `cd example && fvm flutter run`. Simulators and desktop mice don't reproduce touch gestures well, and mouse drags are ignored by design.
4. Reproduce your problem. Pick one sheet variant and one physics override, label each gesture in the overlay (`refresh`, `dismiss` or `scroll`), and copy the session. [docs/analysis/scroll-distinction-and-logs.md](docs/analysis/scroll-distinction-and-logs.md) explains how to read the `[RSheet]` log and which number to change for each kind of miss.
5. For a threshold or behaviour change, add a replay of the failing gesture to `test/arbitrator_test.dart`. It should fail on the old config and pass on the new one. Add a widget test in `test/refresh_indicator_bottom_sheet_test.dart` if the user-visible result changes.
6. Check the lowest supported SDK too if you touch widget lifecycle code: Flutter 3.44 with `flutter pub downgrade`. It already caught one bug that 3.50 didn't.
7. Open a PR. Say what you wanted to happen, what happened, and attach the copied session log. Keep the change small and one idea per PR.

If you find a bug and don't have a fix, open an issue with the session log. That alone is useful.

### Propose a different model

The decision logic here is one model: velocity, straightness and timing thresholds, decided on every pointer move. It may be the wrong one. If you think arbitration should work differently, say so with a PR, not only an issue.

- Read [docs/analysis/scroll-distinction-and-logs.md](docs/analysis/scroll-distinction-and-logs.md) first. It describes the model in the code: who may leave the list, the states, what separates a refresh from a dismiss, and what a release commits to.
- Read [docs/analysis/refresh-vs-dismiss-arbitration.md](docs/analysis/refresh-vs-dismiss-arbitration.md) for the designs that were already rejected, and why.
- Open a PR that adds a document under `docs/analysis/` describing your model in the same terms: the states, the inputs, the transitions and the release rules. Show which of the labelled gestures in the logs it classifies differently and why that is better.
- Code is optional at that stage. A working replay in `test/arbitrator_test.dart` that the current model fails is the strongest argument.

## The real fix belongs in Flutter

This package is a workaround that sits on top of the framework. The sheet's drag handlers are private. The route's animation controller is `@protected`. The gesture arena has no way for a losing recognizer to take a gesture back. A proper fix is a framework change, and I'd be happy to see this package made obsolete by one. If you have a better seam, open an issue or a PR.

## AI disclosure

I built this with AI. The code, the tests, the design analysis in `docs/` and this README were written with Claude (Anthropic) through Claude Code. I set the direction, ran the example on devices, reported what felt wrong, and decided what stays. The thresholds and behaviour changes in section 9 of the analysis doc came from those device runs.

I am responsible for what is published here. Still, treat it like code from anyone: read it, test it on your own devices, and don't assume it is correct because it looks tidy. The links in the table above were fetched and read during the research, except Stack Overflow, which refused the fetch; that row is from a summary and is unverified.

## License

MIT. Copyright (c) 2026 Corkscrews. See [LICENSE](LICENSE).
