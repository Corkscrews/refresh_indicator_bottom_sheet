# Fixing refresh versus dismiss in Flutter itself: plan

Status: plan only. Nothing here is implemented or tested.

This is the upstream counterpart of [refresh-vs-dismiss-arbitration.md](refresh-vs-dismiss-arbitration.md), called "the package doc" below. That document works around the problem from outside the framework. This one says what to change inside it.

Sources read on 2026-11-15:

- `../material_ui-fork`: a fork of flutter/packages (`origin` is `ppamorim/packages`), `main` at `66784038c` (2026-11-13). It is a sparse checkout that holds only `packages/material_ui`, at version 1.11.0. Paths below starting with `packages/material_ui/` are in this checkout. This is where the work happens.
- `packages/cupertino_ui` 1.1.6 at the same commit, read with `git show` because it is outside the sparse checkout.
- flutter/flutter `master` at `e8ac49ab53` (2026-11-14). That checkout has since been removed from disk. Paths starting with `packages/flutter/` refer to it and cannot be re-checked locally.

Line numbers will drift. Symbol names are the stable reference.

## Summary

1. **Nothing breaks for an app that upgrades and changes no code.** That is the first constraint on every decision below. Section 2 states the rules and how each is tested.
2. **The earlier draft of this plan had a breaking change and it is gone.** It copied Cupertino's `scrollableBuilder`, which forces `builder` to become nullable. The API is now one optional `bool` that defaults to `false`, and `builder` is untouched (section 4.2).
3. **Two PRs to `material_ui`.** PR 1 lets a list inside a modal bottom sheet drag the sheet (flutter/flutter#36283). PR 2 lets a `RefreshIndicator` share that pull. PR 2 depends on PR 1.
4. **The stock `RefreshIndicator` gets no new public API.** It gains one private ability: being cancelled when the sheet takes the pull.
5. **The policy is one rule:** while the indicator is pulling, a fast downward pull hands the gesture to the sheet; anything else stays with the indicator. Thresholds are private constants.
6. **PR 2 waits for data.** Experiments E1, E2, E4 and E6 from the package doc have not been run.
7. **One optional PR to flutter/flutter** removes the duplicated sheet scroll position. It fixes nothing by itself and comes last.

## 1. Where the code lives

| Piece | Repository | File |
|---|---|---|
| `BottomSheet`, `ModalBottomSheetRoute`, `showModalBottomSheet` | flutter/packages | `packages/material_ui/lib/src/bottom_sheet.dart` |
| `RefreshIndicator` | flutter/packages | `packages/material_ui/lib/src/refresh_indicator.dart` |
| `CupertinoSheetRoute` and `_CupertinoSheetScrollPosition` | flutter/packages | `packages/cupertino_ui/lib/src/sheet.dart` |
| Scroll position, drag controller, `DraggableScrollableSheet` | flutter/flutter | `packages/flutter/lib/src/widgets/` |

Evidence that `material_ui` is the right target:

- flutter/flutter#36283 is open and labelled `p: material_ui` and `package` (checked 2026-11-15).

`material_ui` declares `sdk: ^3.13.0` and `flutter: ">=3.47.0"`. The fix must use only framework APIs that exist in Flutter 3.47.0, so that this constraint does not move.

## 2. Compatibility rules

The contract: an app that upgrades `material_ui` and changes no code compiles as before and behaves as before. Every rule below is a consequence.

### 2.1 Public API added by both PRs together

| Where | Addition |
|---|---|
| `showModalBottomSheet` | One optional named parameter, `bool enableDragFromScrollable = false` |
| `ModalBottomSheetRoute` | The same parameter, and a `final bool` field |
| `BottomSheet` | The same parameter, and a `final bool` field |
| `RefreshIndicator`, `RefreshIndicatorState`, `RefreshIndicatorStatus` | Nothing |
| `showBottomSheet`, `Scaffold.showBottomSheet`, `BottomSheetThemeData` | Nothing |

`enableDragFromScrollable` is a working name. `isScrollControlled` already exists and means something else (height), so the name must not suggest it.

### 2.2 Rules

1. **No existing signature changes.** No parameter, field or typedef changes its type, nullability, `required` status, default or order. `builder` stays `required` and stays `WidgetBuilder` in all three places (`bottom_sheet.dart:101` and `:122`, `:887` and `:914`, `:1324`).
2. **Off by default, and off means identical.** With the flag at `false`, `_BottomSheetState` creates no controller and inserts no widget. The widget tree, the gesture arena, semantics and goldens are the same as today.
3. **No existing test is edited.** If a PR needs to change an expectation in an existing test file, that is a break. Stop and redesign.
4. **No new enum value.** `RefreshIndicatorStatus` keeps its six values. A new value breaks every exhaustive `switch` in apps. A takeover reports the existing `canceled`.
5. **No public member on `RefreshIndicatorState`.** Apps hold `GlobalKey<RefreshIndicatorState>`, so anything added to that class is API. The cancel hook is a separate private object (section 5.2).
6. **No change to existing behaviour constants.** `_kMinFlingVelocity`, `_kCloseProgressThreshold`, the sheet's drag recognizer and the gesture arena stay as they are.
7. **No change to `pubspec.yaml`.** No new dependency and no higher `sdk` or `flutter` bound. Run the tests on the lower bound too; Flutter 3.47.2 and 3.50.0 are both installed under FVM.
8. **No deprecation and no `lib/fix_data` entry.** Nothing is renamed or replaced.
9. **The pending changelog says `version: minor`.** Never `major`.

### 2.3 Why not Cupertino's `scrollableBuilder`

`cupertino_ui` added `scrollableBuilder` by making `CupertinoSheetRoute.builder` a `WidgetBuilder?` (`sheet.dart:744`) and deprecating `builder` on `showCupertinoSheet`. Doing the same in Material changes `ModalBottomSheetRoute.builder` and `BottomSheet.builder` from `WidgetBuilder` to `WidgetBuilder?`. Any subclass or wrapper that calls `route.builder(context)` or passes `sheet.builder` on stops compiling. That violates rule 1, so it is rejected.

### 2.4 What remains

- A new field on a class breaks code that `implements BottomSheet` or `implements ModalBottomSheetRoute`. This was equally true of every field added before, such as `sheetAnimationStyle`. I know of no such code and did not search pub.dev.
- An app that opts in after PR 1 and before PR 2 has an unreachable refresh (section 4.3). Ship both PRs in the same `material_ui` release if possible. Otherwise the PR 1 API docs must say that `RefreshIndicator` is not supported yet.

## 3. What the package needed that upstream does not

| Package workaround | Why it existed | Upstream replacement |
|---|---|---|
| `RefreshSheetRoute` subclass | The route's controller is private | The position calls `_BottomSheetState`'s existing drag handlers |
| Linear curve plus `createSimulation` override | `Split` curve rebinding is private, so writing the controller did not track the finger | Those handlers already call `onDragStart` and `onDragEnd`, which do the rebinding (`_ModalBottomSheetState.handleDragStart`, `handleDragEnd`) |
| Own close logic (`closeVelocity`, `closeProgress`, the route-popping guard) | `_handleDragEnd` is private | `_handleDragEnd` itself, with `_kMinFlingVelocity`, `_kCloseProgressThreshold` and `_dismissUnderway` |
| Own indicator widget and state | A stock indicator cannot be cancelled from outside | A private cancel on the stock indicator |
| `Listener` and `PointerHistory` for velocity | `applyUserOffset` receives no timestamp | A `Drag` proxy inside the position (section 5.3) |
| Reading sheet height from an ancestor render box | `_childHeight` is private | `_childHeight` |
| `RefreshSheetArbitrationConfig`, 20 fields | Tuning on a device | Private constants, set from the experiments |
| `showRefreshModalBottomSheet` | The stock function cannot push the subclass | One opt-in flag on the stock function |

## 4. PR 1: a list can drag the modal bottom sheet

Target: `packages/material_ui`. Addresses flutter/flutter#36283.

### 4.1 Change

Port `_CupertinoSheetScrollController` and `_CupertinoSheetScrollPosition` (`packages/cupertino_ui/lib/src/sheet.dart:1267` and `:1307`) into `bottom_sheet.dart` as private classes. That position is about 90 lines and is the fix that closed #161687 for Cupertino. It is a copy, not an import, so `material_ui` gains no new dependency on `cupertino_ui` internals.

`_BottomSheetState` owns the controller and passes its existing private handlers as the callbacks:

| Position callback | `_BottomSheetState` |
|---|---|
| drag start | `_handleDragStart` (`:273`) |
| delta for the sheet | `_handleDragUpdate` (`:280`), which does `animationController.value -= primaryDelta / _childHeight` |
| drag end with velocity | `_handleDragEnd` (`:292`), which closes or springs back |
| "is the sheet dragged down" | `animationController.value < 1.0` |

The handlers take `Drag*Details`, so the position builds them. `_handleDragUpdate` reads only `primaryDelta`.

The routing rule is Cupertino's, unchanged:

```dart
if (!listShouldScroll && (delta > 0 || sheetIsDraggedDown())) {
  onDragUpdate(delta);            // the sheet
} else {
  super.applyUserOffset(delta);   // the list
}
```

`goBallistic` ends the sheet drag and calls `super.goBallistic(0)` when the sheet owned the release, as the Cupertino position does. `ScrollDragController.end` negates the finger velocity before `goBallistic`, so the sign must be flipped back before building the `DragEndDetails` for `_handleDragEnd`.

The controller is created only when `enableDragFromScrollable` and `enableDrag` are both true.

### 4.2 API

```dart
showModalBottomSheet(
  context: context,
  enableDragFromScrollable: true,     // new, defaults to false
  builder: (BuildContext context) {
    return ListView.builder(...);     // no controller: it inherits the sheet's
  },
);
```

When the flag is on, `_BottomSheetState` wraps the result of `builder` in a `PrimaryScrollController` that carries the sheet's controller. `material_ui` already hands a controller to a list this way in `dropdown.dart:368` and `menu_anchor.dart:3797`.

What the app author needs to know:

- On Android and iOS a vertical scroll view with no `controller` inherits the primary controller without further code. On desktop and web it needs `primary: true`. This is the stock `PrimaryScrollController` behaviour and is not changed.
- A list with its own `controller` does not take part. It scrolls as it does today. To take part it must use `PrimaryScrollController.of(context)` in place of its own controller. Cupertino has the same limit.

The flag is opt-in because turning this on for every sheet changes what a downward drag on an existing list does. Making it the default would be a behaviour break and is not proposed.

### 4.3 Behaviour after PR 1, in a sheet that opted in

| Pull, list at offset 0 | Result |
|---|---|
| Downward drag on the list | The sheet follows the finger. Release closes or springs back by the stock thresholds. |
| Reverse upward before release | The sheet returns to fully open, then the list scrolls. One gesture. |
| Drag that starts mid-list and reaches the top | The sheet takes over at the top. This is Cupertino's behaviour. The package keeps such a gesture on the list; see open question 2. |
| `RefreshIndicator` around the list | The indicator starts and then gets no overscroll, so it never arms. Refresh is unreachable. PR 2 fixes this. |

A sheet that did not opt in behaves as it does today in all four rows.

`CupertinoSheetRoute.scrollableBuilder` with a `CupertinoSliverRefreshControl` should have the last row's problem today, because its position never lets `pixels` go negative during a top pull. I read that from the code and did not run it.

## 5. PR 2: the refresh indicator shares the pull

Target: `packages/material_ui`. Depends on PR 1. It changes behaviour only inside a sheet that set `enableDragFromScrollable`.

### 5.1 Rule

While the indicator is pulling, the list keeps receiving the deltas through `super.applyUserOffset`. Stock overscroll happens, stock notifications reach the stock `RefreshIndicator`, and it behaves as it does outside a sheet on both platforms. The only new decision is when to stop:

```dart
// in the sheet scroll position, before the PR 1 rule
if (toSheet && !sheetIsDraggedDown() && !_sheetTookOver && indicator.isPulling) {
  if (!_isFastPull() || indicator.isArmed || _pastTakeoverDeadline()) {
    super.applyUserOffset(delta);   // the pull stays a refresh
    return;
  }
  indicator.cancelPull();           // the sheet takes over, refresh will not fire
  _sheetTookOver = true;            // reset in drag()
}
```

`_sheetTookOver` is needed because `_dismiss` is `async` and starts with `await Future<void>.value()` (`refresh_indicator.dart:588`). The status changes one microtask later. Two move events delivered in one batch would otherwise cancel twice and call `onStatusChange(canceled)` twice.

Consequences that fall out without more code:

- A drag that starts mid-list never starts the indicator (`_shouldStart` needs `extentBefore == 0.0`), so `isPulling` is false and PR 1's rule applies.
- A refresh in flight is not `isPulling`, so a top pull moves the sheet. This is section 5.6 of the package doc.
- No indicator in the tree: nothing registered, PR 1's rule applies.

### 5.2 Wiring

`RefreshIndicator` sits between the sheet and the scrollable, and the two are separate Dart libraries, so neither can reach the other's private members.

- A new file under `lib/src/` that `material_ui.dart` does not export holds an inherited scope and a small abstract handle class. Both are invisible to apps. The package already keeps internals out of its API both ways: unexported files (`_about_io.dart`) and `hide` on an export (`scaffold.dart`).
- `BottomSheet` puts the scope above its child only when `enableDragFromScrollable` is on.
- `RefreshIndicatorState` looks the scope up in `didChangeDependencies` (`:421`), registers a handle, and removes it in `dispose` (`:437`). Outside such a sheet the lookup returns null and nothing else runs.
- The handle is a private class in `refresh_indicator.dart` that holds the state. `RefreshIndicatorState` must not implement the handle interface itself, because that would add `isPulling`, `isArmed` and `cancelPull` to a public class (rule 5).
- The handle exposes three things read from existing state: `isPulling` (`_status` is `drag` or `armed`), `isArmed`, and `cancelPull()`, which calls the existing `_dismiss(RefreshIndicatorStatus.canceled)`.

`_dismiss(canceled)` already does what is needed. It sets the status to `canceled`, retracts the spinner, and the `ScrollEndNotification` branch does nothing for that status, so `onRefresh` is not called. An app listening to `onStatusChange` sees `drag`, `canceled`, `null`, which is what an abandoned pull reports today.

### 5.3 Knowing the pull is fast

`applyUserOffset(double delta)` carries no time. The position already overrides `drag()` and can wrap the `Drag` it returns. `Scrollable` calls `update(DragUpdateDetails)` on that object (`packages/flutter/lib/src/widgets/scrollable.dart`), and the details carry `sourceTimeStamp` and `globalPosition`. The proxy feeds a `VelocityTracker` and forwards the call. No `Listener` and no pointer bookkeeping.

If `sourceTimeStamp` is null, or the tracker has too few samples, the pull counts as slow.

### 5.4 Policy and constants

| Constant | Start value | Source |
|---|---|---|
| Takeover velocity | 1100 px/s | `dismissVelocityTop` in the package; hypothesis E2 |
| Takeover deadline | 200 ms from drag start | `takeoverDeadline`; hypothesis E4 |

Both are private, like `_kMinFlingVelocity`.

The upstream rule locks the pull to the indicator once it is armed or the deadline has passed. That is the package's `refreshCanBecomeDismiss: false`, and it is **not** the package's current default. The reason for choosing it upstream: an armed spinner tells the user to release, and a lift-off flick that instead closes the sheet discards both the refresh and the sheet. This is a product decision; see open question 1.

The package also checks straightness, axis dominance, jitter, instantaneous velocity, a minimum run and a pointer-down band. None of those go upstream at first. Add one only when an experiment or a failing test shows a misfire it would prevent.

### 5.5 Differences from the package's behaviour

| Case | Package | Upstream plan |
|---|---|---|
| List while the indicator pulls | Pinned at offset 0 on both platforms | Stock: clamps on Android, bounces on iOS |
| Sheet reversed back to fully open | Indicator reappears at its earlier pull | Indicator stays cancelled for that gesture; the list scrolls |
| iOS, at the moment of takeover | List is at offset 0 | List is still stretched by the bounce and springs back on release |
| Indicator on iOS | `CupertinoActivityIndicator` | Whatever `RefreshIndicator` or `RefreshIndicator.adaptive` already draws |

The third row is the one to look at on a device. With the deadline the stretch is a few pixels. If it looks wrong, the fallback is the package's approach: pin the list and add pull to the indicator directly, which costs a second method on the private handle.

## 6. Optional PR 3: one scroll position in flutter/flutter

Target: flutter/flutter, `packages/flutter/lib/src/widgets/`. That repository is not cloned at present.

After PR 1 the same position exists three times: `_DraggableScrollableSheetScrollPosition`, `_CupertinoSheetScrollPosition`, whose header comment says it is a modified copy of the first, and the Material one. A public widgets-layer controller that takes the four callbacks would let `cupertino_ui` and `material_ui` delete theirs.

Do this last and only if the maintainers ask for it. It adds public API to the framework, the packages cannot use it until their minimum SDK moves, and it fixes no user-visible bug.

## 7. Tests

Model: the `draggable scrollable CupertinoSheetRoute` group in `packages/cupertino_ui/test/sheet_test.dart`.

Compatibility, both PRs. These guard section 2:

- every existing test in `bottom_sheet_test.dart`, `persistent_bottom_sheet_test.dart`, `bottom_sheet_theme_test.dart` and `refresh_indicator_test.dart` passes with no edit;
- flag absent: the sheet adds no `PrimaryScrollController` above the content, and a downward drag on a list at the top overscrolls the list and leaves the sheet where it is;
- flag absent, `RefreshIndicator` in the sheet: a slow pull and a fast pull both do what they do today;
- flag on, list with its own controller: the list is not attached to the sheet's controller and scrolls as today;
- `enableDrag: false` with the flag on: nothing is installed.

PR 1, in `packages/material_ui/test/bottom_sheet_test.dart`, each under Android and iOS physics:

- downward drag on the list moves the sheet one to one, read after each `moveBy`;
- slow release above half springs back; below half, or a fling, closes;
- reverse upward returns the sheet and then scrolls the list;
- drag starting mid-list scrolls, then moves the sheet at the top;
- a list too short to scroll still drags the sheet;
- a `reverse: true` list does not hand over;
- a drag that lands during the entry animation does not leave the sheet stuck.

PR 2, in `packages/material_ui/test/refresh_indicator_test.dart`:

- slow pull arms and `onRefresh` runs; the sheet's position never changes;
- fast pull moves the sheet, `onRefresh` is not called, and `onStatusChange` reports `drag`, `canceled`, `null` with `canceled` exactly once;
- armed, then a fast lift: `onRefresh` runs and the sheet stays;
- pull during a running refresh moves the sheet and does not start a second refresh.

Port the widget tests in this repo's `test/refresh_indicator_bottom_sheet_test.dart` where the behaviour is the same. The trace replays in `test/arbitrator_test.dart` test a class that does not go upstream.

Also for each PR: an example under `packages/material_ui/example/lib/bottom_sheet/` (next free name is `show_modal_bottom_sheet.3.dart`) and a file in `packages/material_ui/pending_changelogs/` copied from `template.yaml` with `version: minor`.

## 8. Order of work

1. Comment on flutter/flutter#36283 with the approach in sections 2, 4 and 5 and ask whether an opt-in flag with `PrimaryScrollController` is acceptable. `packages/material_ui` is already confirmed by the issue's labels.
2. Finish the fork's setup. The sparse checkout lacks three things:

   ```bash
   cd ../material_ui-fork
   git remote add upstream https://github.com/flutter/packages.git
   git sparse-checkout add script packages/cupertino_ui
   git switch -c modal-sheet-drag-from-scrollable
   ```

   `script/flutter_goldens` is a `path:` dev dependency of `material_ui`, so `flutter pub get` cannot resolve without it. `script/tool` is the repository tool that `AGENTS.md` requires for format, analyze and test. `packages/cupertino_ui` holds the position to port. There is no `upstream` remote yet, so the fork cannot follow flutter/packages.
3. Before each PR, from the fork root:

   ```bash
   dart pub get -C script/tool
   dart run script/tool/bin/flutter_plugin_tools.dart format --packages material_ui
   dart run script/tool/bin/flutter_plugin_tools.dart analyze --packages material_ui
   dart run script/tool/bin/flutter_plugin_tools.dart dart-test --packages material_ui
   ```

   Run the tests on Flutter 3.47.2 and on 3.50.0 (rule 7).
4. Run E1, E2, E4 and E6 from the package doc on one Android and one iOS device with this repo's tuning screen. They set the two constants in 5.4 and decide open question 1.
5. PR 1.
6. PR 2, with the experiment data in its description.
7. PR 3 if asked.
8. When PR 2 is in a `material_ui` release, this package reduces to a thin wrapper or is retired.

## 9. Not doing

- Any change that breaks a rule in section 2.
- Making `builder` nullable, or adding `scrollableBuilder` to the classes (section 2.3).
- Turning the behaviour on by default.
- A public arbitration config. Twenty tunables are for finding values, not for an API.
- Upstreaming the package's own indicator or `RefreshSheetArbitrator`.
- Changing the arena or adding a recognizer. Section 4 of the package doc gives the reasons and they still apply.
- Persistent bottom sheets (`Scaffold.showBottomSheet`). `BottomSheet` gets the flag, so they can follow, but they are not part of the report.
- `CupertinoSliverRefreshControl` inside `CupertinoSheetRoute`. Same shape of problem, different package, and it needs its own check first.

## 10. Open questions

1. **Armed lock.** Section 5.4 locks an armed pull to the indicator. The package defaults the other way. E6 and the maintainers decide.
2. **Arrive-at-top handoff.** PR 1 inherits it from Cupertino. If Material should not have it, the position must record at `drag()` whether the list was at the top and at rest, as the package does.
3. **iOS stretch at takeover**, section 5.5.
4. **Pointer cancel.** An accepted scroll drag reports a cancel as a normal end, so a cancelled fast pull could close the sheet. The stock sheet recognizer behaves the same way, so this is parity and not a regression. Confirm with a test.
5. **Mouse and trackpad drags.** The package excludes them. The Cupertino position does not. Follow Cupertino unless a reviewer objects.
6. **`notificationPredicate` and nested scrollables.** The registration in 5.2 assumes one vertical scrollable under the indicator, as `defaultScrollNotificationPredicate` does.
7. **Reviewers may ask for Cupertino's `scrollableBuilder` shape.** The only form that keeps rule 1 is to add it to the `showModalBottomSheet` function alone and make that function's `builder` argument optional. Existing calls still compile, and the class fields do not change. Offer it only if asked.
8. **Changelog convention.** `ci_config.yaml` sets `release: batch: true` and recent PRs added files to `pending_changelogs/`, so the plan does that. `AGENTS.md` describes the general rule of editing `CHANGELOG.md` and `pubspec.yaml`. The flutter/flutter page that explains batch releases was not read.
