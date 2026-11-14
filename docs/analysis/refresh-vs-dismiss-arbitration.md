# Pull-to-refresh versus drag-to-dismiss in a modal bottom sheet: design plan

Status: slices 1, 2 and 3 are implemented. Section 9 lists what the implementation changed against this plan. Where the two disagree, section 9 and the code win. The experiments in section 7 have not been run.

SDK the repo resolves: Flutter 3.50.0 (framework `ab2912035e`, Dart 3.14.0), from `.fvmrc`.
Every `file:line` below is in `packages/flutter/lib/src/` of that SDK and was rechecked against it.
Line numbers will drift on other versions; the symbol names are the stable reference.
`package:flutter/material.dart` and `package:flutter/cupertino.dart` are deprecated in this SDK. The package and the example import `material_ui` and `cupertino_ui`. The framework files cited here still live under `packages/flutter/lib/src/`.

## Decision summary

1. The scrollable keeps the pointer. The package diverts its drag deltas, one pointer move at a time, to exactly one of three targets: the list, the refresh indicator, or the sheet.
2. The diversion point is `ScrollPosition.applyUserOffset` and `goBallistic`, through a package-owned `ScrollController`. The framework's own Cupertino sheet uses this same seam (`cupertino/sheet.dart:1200`, `_CupertinoSheetScrollPosition`).
3. The sheet is moved through the route's own `AnimationController`, with the same formula the stock handler uses. Reaching that controller needs a three-line `ModalBottomSheetRoute` subclass. No custom sheet widget, no copied framework code.
4. `RefreshIndicatorOpt` stops delegating to `RefreshIndicator` when it is inside that route and runs its own indicator state, because a stock `RefreshIndicator` cannot be cancelled from outside once it is armed (section 3.3). Outside the route it stays the pass-through it is today.
5. A pure-Dart arbitrator decides the target on every pointer move from the inputs in section 5. All thresholds live in one config object.
6. `refreshCanBecomeDismiss` defaults to true: a fast pull hands the sheet over even after the indicator arms or `takeoverDeadline` passes. Set it false and a tracked pull stays a pull; the sheet can take over only with a fast pull, within `takeoverDeadline` of pointer down and before the indicator arms (section 9).

## 1. Failure

### Widget tree in `example/lib/main.dart`

```
showModalBottomSheet(enableDrag: true, isScrollControlled: false, no drag handle)
└─ ModalBottomSheetRoute
   └─ _ModalBottomSheet                       material/bottom_sheet.dart:651
      └─ _BottomSheetLayoutWithSizeListener   caps height at 9/16 (line 621)
         └─ BottomSheet
               └─ _BottomSheetGestureDetector    VerticalDragGestureRecognizer A (line 1437)
               └─ Material
                  └─ RefreshIndicatorOpt → RefreshIndicator
                     └─ ListView.builder (30 rows, AlwaysScrollableScrollPhysics)
                        └─ Scrollable         VerticalDragGestureRecognizer B (widgets/scrollable.dart:791)
```

The list fills the sheet. Every pointer that lands on the sheet lands on the `Scrollable`.

### Who wins the arena

Both recognizers are `VerticalDragGestureRecognizer`s with the same slop (`kTouchSlop`, 18 px, `gestures/constants.dart:65`). They receive the same `PointerMoveEvent` through the pointer router, in the order they registered, and the deeper widget registers first. When the slop is crossed, B calls `resolve(GestureDisposition.accepted)` first (`gestures/monodrag.dart:709`). The arena is already closed, so `GestureArenaManager._resolve` goes straight to `_resolveInFavorOf` (`gestures/arena.dart:226-240`) and A is rejected.

That resolution is final for the pointer. Nothing in the arena lets A take over later in the same gesture.

Result:

| Pull at list offset 0 | What happens |
|---|---|
| Downward drag on the list | B wins. On Android the list emits `OverscrollNotification`; on iOS it bounces. `RefreshIndicator` displaces and may arm. The sheet never moves. |
| Downward drag on a non-scrolling region | A wins and the sheet tracks the finger. The example has no such region. |

`AlwaysScrollableScrollPhysics.shouldAcceptUserOffset` returns `true` unconditionally (`widgets/scroll_physics.dart:1086`), so B is in the arena even when the content is shorter than the sheet.

## 2. Prior reports

Eight of the nine links were fetched on 2026-11-13. Stack Overflow refused the fetch; that paragraph rests on the summary in the task brief and is marked.

**flutter/flutter#36283, "Can't swipe to dismiss scrollable Bottom Sheet"** (open, P2). dnfield's answer in 2019 is to use `DraggableScrollableSheet`. In July 2024 notsag-dev posted a `NotificationListener` that pops the route when the list is at the top, the user is dragging, and `OverscrollNotification.overscroll < -3`. Its author says it "hides it all at once", that "you don't want the momentum of the scroll up to hide your bottom sheet", that iOS bounce physics emit no overscroll so the list must be forced to `ClampingScrollPhysics`, and that "this isn't an actual solution but a patch". In March 2025 rydmike cited the Material 3 swipe-down guideline and said it is "not possible in Flutter when we have a sheet with scrolling content". Not this fix: it pops on a threshold, the sheet never tracks the finger, and it removes iOS bounce.

**flutter/flutter#24489, "ScrollPhysics do not trigger pull down dismiss event of bottomsheet"** (closed as a duplicate of #36283). A commenter observed that a list with too few items to scroll lets the sheet dismiss, and a list that scrolls does not. That is the arena result in section 1: without scroll extent the `Scrollable` drops its recognizer, so the sheet's recognizer is alone. Not this fix: it only works by having no competing scrollable, which also means no pull-to-refresh.

**flutter/flutter#31739, "DraggableScrollableSheet gets stuck and won't move"** (closed, fixed by PR #31832). The issue itself is a different bug. The relevant part is a follow-up comment about the Google I/O filters sheet with `initialChildSize` and `minChildSize` at 1.0, which "breaks the ability to scroll the sheet and only ever dismisses it when you interact". dnfield answered that the widget is not meant to sit at 1.0. Not this fix: a sheet pinned at full extent turns every downward drag into a dismiss, so there is no room for refresh.

**flutter/flutter#161687, "Cupertino Sheet should have drag to dismiss and nested scrolling work together"** (closed as completed by PR #177337, January 2026). The report is that one drag goes entirely to the scroll view or entirely to the sheet and "we can't switch back and forth". A commenter's gist forwarded scroll notifications into `_CupertinoDownGestureController` and needed the `bottom_sheet_scroll_physics` package; its author called it "hacky". The merged fix is in the pinned SDK and is the useful part: a `ScrollController` whose position overrides `applyUserOffset` and `goBallistic` (section 3.4). Not this fix: it is Cupertino-only, it has two targets rather than three, and it has no refresh indicator to arbitrate against. This plan reuses its seam, not its policy.

**flutter/flutter#116427** (closed as a duplicate). A fast flick on a `DraggableScrollableSheet` inside `showModalBottomSheet` snaps the sheet and stops scrolling the inner list, and the reporter asks why there is no dismiss threshold. A triager could not confirm the flick problem on master. Not this fix: it shows that sharing one position between extent and list gives the app no say in when a flick becomes a dismiss.

**flutter/flutter#95673 and #127236.** #95673 (closed as a duplicate of #83273) reports that `enableDrag: false` is ignored once a `DraggableScrollableSheet` is the child. #127236 proposed `shouldCloseOnMinExtent`, closed by PR #127339. Both are confirmed in the pinned SDK: `_BottomSheetState.extentChanged` (`material/bottom_sheet.dart:327`) calls `onClosing` when a `DraggableScrollableNotification` reports `extent == minExtent` and `shouldCloseOnMinExtent`, without consulting `enableDrag`. Not this fix: the close is a binary event at min extent. It says nothing while the finger is moving.

**Stack Overflow 57835416** (not fetched; unverified). Per the task brief: dragging the list only scrolls it, and the sheet moves only from a non-scrolling handle. That is the arena result in section 1. Not this fix: a handle is a second affordance, not an answer for the list area.

**jamesblasco/modal_bottom_sheet.** The README lists "support for inside scrollview + dragging down to close (`showModalBottomSheet` won't work correctly with scrollviews" and requires the app to pass `ModalScrollController.of(context)` to its scroll view. Issue #135 (closed by PR #164): with real scroll extent, a downward drag "will simply show the android 'scroll edge' indicator, but wont even move the bottom sheet". Issue #47 (open): iOS bounce and dismiss collide; a 2024 comment proposes "clamping behaviour at the top when scrolling down starts at the top edge", and a later one says "it seems not possible to work around the issue". Closing by a fast drag on a scroll view is still on the README roadmap. Not this fix: it is a replacement route and sheet stack with no refresh arbitration. The plan takes two ideas from it: own the scroll controller, and split the top edge by where the gesture started.

**flutterpro.design, "Close the sheet by swiping down at the top".** States that with `showModalBottomSheet` "a swipe on the list only scrolls. At the top it just stops, the sheet doesn't move", and points to `scroll_drag_detector` and `stupid_simple_sheet` by the same author. It notes that with `scroll_drag_detector` "moving the sheet, the resistance, and the close-or-snap-back decision stay on you". Not this fix: it is a pointer to other packages and, again, has no refresh indicator in the picture.

## 3. Gesture ownership, verified against the SDK

### 3.1 The sheet

| Fact | Where |
|---|---|
| `_kMinFlingVelocity = 700.0`, `_kCloseProgressThreshold = 0.5`, default height ratio `9.0 / 16.0` | `material/bottom_sheet.dart:30-32` |
| The drag moves the sheet with `animationController.value -= primaryDelta / _childHeight` | `_handleDragUpdate`, line 278 |
| On release: close if `velocity.dy > 700`, else close if `value < 0.5`, else `forward()` | `_handleDragEnd`, lines 303-318 |
| The recognizer is built privately, with `onlyAcceptDragOnThreshold = true` | `_BottomSheetGestureDetector`, lines 1437-1468 |
| The route keeps its controller in a private field | `ModalBottomSheetRoute._animationController`, line 1108 |
| Height cap when `isScrollControlled` is false | `_getConstraintsForChild`, lines 615-623 |
| Sheet position is `size.height - childSize.height * animationValue` | `_getPositionForChild`, line 625 |
| `animationValue` is the route animation passed through a curve, except during a stock drag, when `handleDragStart` rebinds it to the linear animation | `_ModalBottomSheetState`, lines 689-749 |

**The stock drag handler cannot be fed pixels from outside.** `_handleDragStart`, `_handleDragUpdate` and `_handleDragEnd` are private methods of a private state class. The recognizer that calls them is created inside a private widget. The only public inputs are `enableDrag`, `showDragHandle` and the observer callbacks `onDragStart` / `onDragEnd`. And because arena resolution is final per pointer, making recognizer A win would give the sheet the whole gesture, with no way to hand the pointer to the indicator or the list afterwards.

What is public: `TransitionRoute.controller` (`widgets/routes.dart:191`), marked `@protected`, so a subclass of `ModalBottomSheetRoute` may read it. `showModalBottomSheet(transitionAnimationController:)` is also public, but it puts creation, vsync and disposal on the app, and the future returned by `showModalBottomSheet` completes at pop, before the exit animation ends, so the obvious `await` then `dispose()` breaks the exit.

### 3.2 The scrollable

| Fact | Where |
|---|---|
| Every drag delta goes through `applyUserOffset`, which calls `setPixels(pixels - physics.applyPhysicsToUserOffset(this, delta))` | `widgets/scroll_position_with_single_context.dart:129-132` |
| Pointer up calls `goBallistic(velocity)`, which asks the physics for a simulation | same file, lines 149-157 |
| Mouse wheel uses `pointerScroll`, a separate path | same file, line 210 |
| `BouncingScrollPhysics.applyPhysicsToUserOffset` applies friction when out of range and does not consult its parent | `widgets/scroll_physics.dart:835` |
| `ClampingScrollPhysics.createBallisticSimulation` returns `null` at the leading edge when velocity points out of range | `widgets/scroll_physics.dart:1021` onward |
| Platform default physics: bouncing on iOS and macOS, clamping elsewhere | `widgets/scroll_configuration.dart:243-257` |
| Render-object listeners see a pointer event before recognizers do, because the binding adds itself last to the hit-test path and routes to recognizers from its own `handleEvent` | `gestures/binding.dart:455`, `537-538` |

### 3.3 RefreshIndicator

The brief says the indicator "arms after the overscroll exceeds `_kDragContainerExtentPercentage`". The source is more specific:

- `_kDragContainerExtentPercentage = 0.25`, `_kDragSizeFactorLimit = 1.5` (`material/refresh_indicator.dart:21-25`).
- It starts only on a `ScrollStartNotification` that has `dragDetails`, with `extentBefore == 0.0` and `_status == null` (`_shouldStart`, lines 405-419). A drag that begins mid-list never starts it in `onEdge` mode. A ballistic arrival has no `dragDetails` and never starts it.
- `_dragOffset` accumulates `OverscrollNotification.overscroll` (Android) or `ScrollUpdateNotification.scrollDelta` (iOS bounce) (lines 440-463).
- The status flips to `armed` when the spinner colour becomes opaque, at about 16.7% of the viewport (`_checkDragOffset`, lines 517-529, with the `Interval(0.0, 1.0 / 1.5)` at line 400).
- `onRefresh` runs only if, at `ScrollEndNotification`, the status is `armed` and `_positionController.value` is 1.0, which is 25% of the viewport (lines 464-471). Below that it cancels.
- While refreshing, new drags are ignored, because `_shouldStart` requires `_status == null`.

**A stock `RefreshIndicator` cannot be steered from outside.** Its only inputs are scroll notifications and `show()`. `notificationPredicate` can hide notifications from it, but hiding them freezes it; it cannot lower `_dragOffset`. An indicator that is armed at 25% and then starved will still fire on the real `ScrollEndNotification`. The model needs "armed, then the sheet takes over, and refresh must not fire", so the indicator state has to live in this package.

### 3.4 Framework precedent for mid-gesture handoff

`_CupertinoSheetScrollPosition` (`cupertino/sheet.dart:1200-1294`) extends `ScrollPositionWithSingleContext` and overrides two methods:

- `applyUserOffset(delta)`: if the list is at the top and the delta is downward, or the sheet is already dragged down, the delta goes to the sheet; otherwise to `super` (lines 1258-1265).
- `goBallistic(velocity)`: ends the sheet drag and calls `super.goBallistic(0)` when the sheet owned the gesture, so the list does not also fling (lines 1268-1286).

It is created by `_CupertinoSheetScrollController.createScrollPosition` (line 1174) and handed to the app through `scrollableBuilder`. Its header comment says it is itself a modified copy of the position inside `DraggableScrollableSheet`. So the framework has done this twice, both times through the scroll position, never through the arena.

### 3.5 Stay on the 9/16 default, or move to a scroll-controlled sheet

Stay on the default for the primary repro. That is the reported configuration.

`isScrollControlled` changes one thing: the height constraint in `_getConstraintsForChild`. It does not change the widget tree, the recognizers, or who wins the arena. `isScrollControlled: true` does not introduce a `DraggableScrollableSheet`. Drag ownership is identical in both.

What it changes for this design is scale. Sheet height sets how many pixels 50% close progress is, and viewport height sets the 25% arm distance. On an 800 px screen the default gives roughly 450 px for both; a full-height sheet gives roughly 800 px. Thresholds are therefore expressed as fractions of the viewport or the sheet where the stock code does so, and the example gets a second entry that opens the same content with `isScrollControlled: true` to check that the fractions hold (section 7).

## 4. Rejected designs

**Pop from an `OverscrollNotification` listener (#36283).** It decides from a threshold and calls `Navigator.pop`. The sheet is either open or animating closed; it is never under the finger, and it cannot spring back. It also only exists where overscroll notifications exist, which excludes iOS bounce.

**Classify at pointer up or `ScrollEndNotification`.** Any design whose first visible effect comes after release fails the definition of fixed: something must be tracking the finger while it is down. A release-time classifier also cannot hand the pointer back, because there is no pointer left.

**`enableDrag: false`, or removing the indicator.** Each removes one of the two gestures the user asked to keep.

**`DraggableScrollableSheet` with min and max at 1.** One shared position, pinned at full extent, means the first downward pixel is a move toward min extent, and min extent closes the sheet (`extentChanged`, line 327). There is no state in which the indicator can own the pull.

**Forcing `ClampingScrollPhysics`.** Its only purpose in the #36283 patch is to make an overscroll notification appear on iOS. It changes how the list feels everywhere, to feed a design that still pops late.

**Forking Flutter**, including copying `_ModalBottomSheet` and `_BottomSheetLayoutWithSizeListener` into the package. The plan needs none of their internals.

**Winning the arena with a package recognizer and re-driving the list through `ScrollPosition.drag`.** This would work, but the package would then own slop, multi-touch strategy, drag start behaviour and fling for the list. Diverting at `applyUserOffset` leaves all of that to the `Scrollable`.

**Injecting a `ScrollPhysics` through `ScrollConfiguration` and diverting in `applyPhysicsToUserOffset`.** It needs no controller, but an app that sets `BouncingScrollPhysics` explicitly bypasses it (section 3.2), it puts side effects in an object the framework treats as an immutable value, and it replaces the app's `ScrollBehavior`.

**Feeding the stock `RefreshIndicator` synthetic scroll notifications.** They would bubble to every other listener in the app (scrollbars, analytics), and the approach depends on the private order of checks in `_handleScrollNotification`.

**Translating the sheet with a `Transform` around the page instead of the route controller.** It tracks the finger, but the barrier does not fade, the barrier's semantics clip is not updated, and `route.animation` no longer describes where the sheet is.

**`showModalBottomSheet(transitionAnimationController:)` instead of a route subclass.** Public, but see 3.1: the app must create, pass twice, and dispose at the right moment.

## 5. The arbitrator

### 5.1 Structure

```
Listener (raw pointer events)            → samples: position, dx, dy, time, pointer count
package ScrollPosition.applyUserOffset   → asks the arbitrator who takes this delta
package ScrollPosition.goBallistic       → asks whether the list may fling
Arbitrator (pure Dart, no widgets)       → state + three outputs: list delta, indicator pull, sheet offset
```

The `Listener` wraps the child of `RefreshIndicatorOpt`. It does not enter the arena. Because of the dispatch order in 3.2, the arbitrator has the new sample before the scroll position asks about the delta from the same event.

The scroll position is the single authority for distributing pixels. For each delta it calls `arbitrator.route(delta, metrics)` and gets back the part the list should apply, which goes to `super.applyUserOffset`. The arbitrator applies the rest to the indicator pull or the sheet offset. Splitting inside one delta matters at boundaries, for example when an upward delta brings the sheet home and the remainder belongs to the list.

### 5.2 Inputs

All are sampled on every pointer move unless marked as captured at pointer down.

| Input | Source | Used for |
|---|---|---|
| Scroll offset at pointer down; within `edgeSlop` of the leading edge | scroll position | eligibility |
| List at rest at pointer down | `position.isScrollingNotifier` | eligibility; rejects a finger that lands on a ballistic or bouncing list |
| Pointer-down position in the widget, as top band or body | `Listener` local position | selects the threshold set |
| Net `dy` and net `dx` since pointer down, and since the last reversal (the "run") | `Listener` | distance gate, axis dominance |
| Path length since pointer down, and for the run | `Listener` | straightness = net displacement / path length |
| Smoothed velocity | `VelocityTracker` (`gestures/velocity_tracker.dart:138`; 100 ms horizon, at least 3 samples) | velocity gate, release commit |
| Instantaneous velocity, last sample `dy / dt` | `Listener` | rejects a stale smoothed estimate when the finger is already slowing |
| Reversals: sign changes of `dy` that exceed `reversalHysteresis` | `Listener` | starts a new run, drives hand-back |
| Jitter: sign changes below the hysteresis within the velocity window | `Listener` | if high, the velocity gate is ignored and only the distance gate applies |
| Time since pointer down | event timestamps | velocity hold-off, takeover deadline |
| Pixels the list can still consume before min and max extent | scroll metrics | whether a delta is "into the list" |
| Current owner and current sheet offset | arbitrator state | hand-back without a new gesture |
| Refresh in flight | indicator state | section 5.6 |
| Pointer count and device kind | `Listener` | one finger, touch or stylus only |

### 5.3 Parameters

One immutable `RefreshSheetArbitrationConfig`. No threshold appears as a literal anywhere else. `V` is the list viewport height and `H` the sheet height.

| Parameter | Start value | Basis |
|---|---|---|
| `edgeSlop` | 1 px | at rest the offset is exactly the min extent |
| `topBandFraction` | 0.33 of `V` | hypothesis |
| `axisDominance` | `abs(dy) >= 2 * abs(dx)` over the run | hypothesis; about 27° either side of vertical |
| `minStraightness` | 0.85 | hypothesis |
| `reversalHysteresis` | 8 px | hypothesis |
| `velocityHoldOff` | 40 ms | the tracker needs three samples |
| `takeoverDeadline` | 200 ms after pointer down | hypothesis; a dismiss flick moves right after the finger lands, a refresh pull is tracked for longer |
| `refreshCanBecomeDismiss` | true | product choice; false keeps a tracked pull on the indicator after arming or after the deadline |
| `minRunForVelocity` | 32 px | keeps the velocity gate off slop noise |
| `dismissVelocityTop` | 1100 px/s | hypothesis. Stock 700 is a release-time gate; a mid-gesture gate must sit above the peak speed of an ordinary refresh pull |
| `dismissVelocityBody` | 800 px/s | hypothesis |
| `armDistance` | 0.25 of `V` | mirrors `_kDragContainerExtentPercentage` |
| `armHysteresis` | 12 px | hypothesis |
| `indicatorTravelFactor` | 1.5 | mirrors `_kDragSizeFactorLimit` |
| `instantVelocityFactor` | 0.5 | the instantaneous-velocity check in 5.5 |
| `jitterFlips` | 2 direction flips within 100 ms | hypothesis |
| `snapDuration`, `retractDuration` | 150 ms, 200 ms | stock `_kIndicatorSnapDuration`, `_kIndicatorScaleDuration` |
| `closeVelocity` | 700 px/s | mirrors `_kMinFlingVelocity` |
| `closeProgress` | 0.5 of `H` | mirrors `_kCloseProgressThreshold` |

Rows marked as hypotheses are what section 7 tries to falsify.

### 5.4 States

| State | What tracks the finger | List | Indicator | Sheet |
|---|---|---|---|---|
| `idle` | nothing | at rest or ballistic | hidden, or showing a running refresh | open |
| `list` | list content | scrolls with stock physics | unchanged | open |
| `indicator` (sub-states `pulling`, `armed`) | indicator | pinned at min extent; no bounce, no stretch or glow | displaced by `pull`; opacity and arrow follow `pull / armDistance`; `armed` when `pull >= armDistance` | open |
| `sheet` | sheet | pinned at min extent | retracting or hidden | translated down by `sheetOffset` |

After pointer up, two things can still be animating, and neither follows a finger: the indicator (`snap`, `refreshing`, `done`, `cancelled`, the same lifecycle as `RefreshIndicatorStatus`) and the sheet (`springing back` or `closing`).

`pull` accumulates only the deltas the indicator owned, the same way stock `_dragOffset` does. `sheetOffset` accumulates only the deltas the sheet owned. Neither is derived from absolute finger position, so a takeover never causes a jump.

### 5.5 Transitions while the pointer is down

**Pointer down.** The gesture is *eligible* if all hold: one pointer, kind is touch or stylus, the offset is within `edgeSlop` of the min extent, and the list is at rest. An ineligible gesture is locked to `list` until the pointer lifts. That covers a drag that starts mid-list and a finger that catches a list in flight.

**Dismiss intent**, evaluated on every move while in `indicator`:

```
vertical  = axis dominance holds and straightness >= minStraightness, over the current run
fast      = time since down >= velocityHoldOff
            and run length >= minRunForVelocity
            and jitter is low
            and smoothed velocity >= dismissVelocity(band)
            and instantaneous velocity >= 0.5 * dismissVelocity(band)
committed = armed or time since down > takeoverDeadline
dismissIntent = vertical and fast and route.enableDrag and one pointer
                and (not committed or refreshCanBecomeDismiss)
```

There is no distance gate. A slow pull never moves the sheet, however long it is. The plan first had one (`dismissDistance`, at 1.5 × `armDistance`), together with an armed dwell lock to stop lift-off flicks. Device testing showed that a pull which turns fast after the indicator is visible must stay a pull (section 9), and the distance gate could only fire after arming. Both were removed.

| From | To | Condition | On screen |
|---|---|---|---|
| `idle` | `list` | first delta of an ineligible gesture; or first delta of an eligible gesture that points into the list | list scrolls |
| `idle` | `indicator` | eligible gesture, first delta is downward, no refresh in flight | indicator starts at pull 0 and fades in |
| `idle` | `sheet` | eligible gesture, first delta is downward, refresh in flight (5.6) | sheet moves from offset 0 |
| `indicator` | `sheet` | `dismissIntent` | indicator retracts over about 150 ms and reports cancelled; sheet starts at offset 0 and takes every further delta one to one |
| `indicator.pulling` | `indicator.armed` | `pull >= armDistance` | spinner fully opaque |
| `indicator.armed` | `indicator.pulling` | `pull < armDistance - armHysteresis` | spinner fades with pull |
| `indicator` | `list` | upward deltas have brought `pull` to 0 and delta remains | indicator gone; the remainder scrolls the list |
| `list` | `indicator` | eligible gesture only: the list is back at min extent and the delta is downward | indicator from pull 0 |
| `sheet` | `indicator` | upward deltas have brought `sheetOffset` to 0 and delta remains, no refresh in flight | sheet fully open; indicator reappears at the `pull` it had at takeover and shrinks with the finger. A second takeover is subject to the same deadline, so in practice it does not happen |
| `sheet` | `list` | same, with a refresh in flight | the remainder scrolls the list |

Notes:

- A reversal never needs a new gesture. Upward deltas unwind the current owner first, then pass to the previous one. This is the hand-back #161687 describes.
- Horizontal movement: if axis dominance fails, `dismissIntent` is false. If the `Scrollable` never crosses vertical slop it never calls `applyUserOffset`, so nothing moves.
- A second finger freezes transitions. The current owner keeps receiving the deltas the `Scrollable` reports, and commit happens when the last pointer lifts.
- Mouse wheel and trackpad scrolling do not produce an eligible gesture and always scroll the list.
- A gesture that starts mid-list and reaches the top with the finger still down stays in `list` and gets the platform's own overscroll. This matches stock `onEdge` behaviour and the test matrix. See open question 3.

### 5.6 Refresh already running

Stock behaviour is to ignore new pulls while refreshing. Here, a second indicator pull has no meaning, so the only thing a top-origin downward pull can do is move the sheet. An eligible downward pull goes straight to `sheet`. The spinner stays visible and travels with the sheet content. If the sheet closes, the `onRefresh` future is left to complete and its result is dropped because the widget is unmounted.

### 5.7 Pointer up: commit what is already tracking

| State at release | Commit |
|---|---|
| `list` | `super.goBallistic(velocity)`; stock fling, bounce or clamp |
| `indicator.pulling` | indicator retracts; `onRefresh` is not called; list gets `goBallistic(0)` |
| `indicator.armed` | indicator snaps to its resting displacement, `onRefresh` runs, indicator leaves when the future completes; list gets `goBallistic(0)` |
| `sheet`, smoothed velocity `>= closeVelocity` downward, or `sheetOffset / H >= closeProgress` | route pops; the exit animation continues from the current controller value |
| `sheet`, otherwise | controller animates back to 1.0 |
| pointer cancel, any state | as `indicator.pulling` or sheet spring-back; never refresh, never close |

The close test uses the stock constants' meaning, applied to a sheet that has already been moving under the finger.

### 5.8 Cases the brief calls out

- **Ballistic arrival at offset 0.** No pointer is down, so `applyUserOffset` is never called and the arbitrator stays `idle`. The list bounces or clamps by its own physics. If a finger lands while it is still moving, the gesture is ineligible.
- **List not at the top.** Ineligible; scroll only.
- **Short content.** With `AlwaysScrollableScrollPhysics`, behaviour is identical to 30 rows: offset 0 is both extents, a downward pull is eligible, an upward pull goes to `list` and gets platform overscroll. The physics stays in the example, since it is part of the repro. The package position also makes the list accept user offsets when it is at min extent inside the route, so a short list without that physics behaves the same. Without that, a short list would drop its recognizer and the stock sheet drag would take every pull, which is the #24489 behaviour with no refresh.
- **iOS and Android.** In `indicator` and `sheet`, deltas at the edge never reach `super.applyUserOffset`, so the physics is not consulted. iOS does not bounce and Android does not emit overscroll. The two platforms behave the same in owned states and keep their own physics in `list`. No physics is forced. This is the "clamp when the gesture starts at the top, bounce when it arrives with velocity" split from modal_bottom_sheet #47.
- **Sheet tracking.** `controller.value -= delta / H`, the stock formula, on the route's controller (section 6.2).
- **Accessibility.** With `showDragHandle: true`, the stock handle sits above the content in its own 48 px band (`material/bottom_sheet.dart:366-412`), has `onSemanticsTap: onClosing`, and is not over a scrollable, so the stock recognizer wins there and the stock handler runs. The arbitrator never sees those pointers. Barrier tap, system back and Escape are untouched. The example should offer a handle toggle so this can be checked with a screen reader.

## 6. API sketch

### 6.1 `RefreshIndicatorOpt`

Constructor parameters stay as they are. One addition:

```dart
const RefreshIndicatorOpt({
  // existing RefreshIndicator-shaped parameters, unchanged
  this.arbitration = const RefreshSheetArbitrationConfig(),
});
```

Build logic:

- `ModalRoute.of(context)` is not a `RefreshSheetRoute`: build a stock `RefreshIndicator`, exactly as today. The existing test keeps passing.
- It is one: build `Listener` → `PrimaryScrollController(controller: package controller)` → own indicator overlay (`RefreshProgressIndicator`, or `CupertinoActivityIndicator` on iOS) → `child`.

The child's vertical scroll view picks the controller up through `PrimaryScrollController`, which is automatic on mobile platforms (`widgets/primary_scroll_controller.dart:39-65`); the package passes all platforms to `automaticallyInheritForPlatforms`. The example's `ListView.builder` needs no change.

Internal, not exported (as built):

- `SheetScrollController` / `_SheetScrollPosition` in `lib/src/sheet_scroll.dart`. They override `hold` (records whether the list was at rest), `drag` (eligibility and `beginDrag`), `applyUserOffset` and `goBallistic`. The physics is wrapped in `AlwaysScrollableScrollPhysics` for user-offset acceptance at the edge.
- `RefreshSheetArbitrator` in `lib/src/arbitration.dart`: `pointerDown(pointer, time, position, local, kind)`, `pointerMove(pointer, time, position)`, `pointerUp(pointer)`, `pointerCancel(pointer)`, `beginDrag(...)`, `double route(delta, room:)`, `ArbitrationCommit release(velocity)`. Tests import it from `src/`. It is not marked `@visibleForTesting`.
- Indicator: an `AnimationController` whose value is `pull / armDistance`. It is drawn with the stock geometry and clipped to the list area below `edgeOffset`. There is no scale-down "done" animation; it retracts by translation instead.

### 6.2 `RefreshSheetRoute`

```dart
class RefreshSheetRoute<T> extends ModalBottomSheetRoute<T> {
  RefreshSheetRoute({required super.builder, super.isScrollControlled = false, ...});

  AnimationController get sheetController => controller!;   // @protected getter, legal from a subclass
}
```

This is the custom route the brief asks to be justified. The justification is section 3.1: the stock handler takes no outside input, and the route controller is reachable only from a subclass or by making the app own it. The subclass adds no behaviour to the stock sheet. Stock handle drags, barrier, theming and semantics are inherited.

One more override is needed for exact tracking. Between drags, the stock sheet position is the controller value passed through `Easing.legacyDecelerate` (3.1), and after a stock handle drag it is passed through a `Split` curve whose split point the package cannot read. Setting `controller.value` from outside would therefore not move the sheet one to one. The subclass removes the problem instead of inverting curves:

- pass `sheetAnimationStyle` with linear `curve` and `reverseCurve` to `super`, so sheet position is always linear in the controller value and the stock `Split` rebinding becomes the identity;
- override `createSimulation({required bool forward})` (`widgets/routes.dart:272`) to return a simulation that follows the easing curve over the stock durations, so entry and exit look as they do today.

`showRefreshModalBottomSheet` mirrors the core of `showModalBottomSheet`. It takes `isScrollControlled`, `enableDrag`, `showDragHandle` and `useRootNavigator`; other parameters can be added when needed.

### 6.3 What stock `showModalBottomSheet` cannot do

- Accept drag pixels from anything but its own recognizer.
- Give its child the route's animation controller.
- Hand a pointer from the scrollable to the sheet, or back, within one gesture.
- Report or override the curve between controller value and sheet position.
- Cancel an armed `RefreshIndicator` without calling `onRefresh`.

## 7. Experiments and manual test matrix

### 7.1 Instrumentation for the example app (later pass)

- A debug overlay on the sheet: current state, `pull`, `sheetOffset`, smoothed and instantaneous velocity, run length, straightness, band.
- A settings sheet with a slider per hypothesis parameter in 5.3.
- One log line per gesture: band, peak smoothed velocity, total travel, duration, every transition with its timestamp, and the commit. The tester marks each gesture as "wanted refresh", "wanted dismiss" or "wanted scroll".
- Entries on the home screen: default 9/16 sheet; `isScrollControlled: true`; 3 rows instead of 30; drag handle on; platform override for iOS and Android physics.

### 7.2 Experiments

Each is run on one Android and one iOS device, default sheet first.

| # | Question | Method | The starting value is wrong if |
|---|---|---|---|
| E1 | Does a velocity gate separate refresh pulls from dismiss pulls? | 30 intended refreshes and 30 intended dismisses per tester, from the top band. Compare peak smoothed velocity before the arm distance. | The two distributions overlap so much that no threshold gets both error rates under 10%. Then velocity alone is not a usable gate and the distance gate must lead. |
| E2 | Is `dismissVelocityTop` at 1100 right? | Same data. | More than 1 in 10 intended refreshes moves the sheet, or more than 1 in 10 intended fast dismisses arms the indicator first. Move it to the crossover point from E1. |
| E3 | Does the pointer-down band carry information? | Repeat E1 from the body. Compare misclassification with band-specific thresholds against one shared set. | The difference is under 5 points. Then remove the band and keep one set. |
| E4 | Is `takeoverDeadline` at 200 ms right? | Intended fast dismisses, including ones where the finger rests briefly first. Record `t=` at the takeover line. | More than 1 in 10 intended dismisses gets no takeover because `t` was past the deadline, or more than 1 in 10 intended refreshes is taken over. |
| E5 | Can a slow drag reach `closeProgress` on a 9/16 sheet? | Slow drag from the bottom of the top band until the finger reaches the screen edge. | The sheet cannot reach 50% before the finger runs out of screen. Lower `closeProgress` for this route; 0.35 is the next value to try. |
| E6 | Does the arming lock (section 9, change 1) stop lift-off flicks? | Arm, hold, lift quickly. 30 trials. | Any trial moves the sheet. |
| E7 | Does hand-back feel continuous? | Pull into `sheet`, reverse to the start, continue upward. | The indicator visibly pops when it reappears. |
| E8 | Do fractions of `V` and `H` transfer? | Repeat E1, E4 and E5 on the full-height sheet. | Error rates differ by more than 5 points. Then use absolute pixels with a cap. |

### 7.3 Manual test matrix

Run every row on iOS physics and Android physics.

| # | Action | Expected while the finger is down | Expected on release |
|---|---|---|---|
| 1 | Soft, short pull from the top band, list at top | Indicator displaces. Sheet and list do not move. | Released past the arm distance: `onRefresh` runs. Released before: indicator retracts. Sheet stays open either way. |
| 2 | Fast downward pull from the top band | Indicator barely appears and retracts. Sheet follows the finger. | Fast release, or past half the sheet: closes. Otherwise springs back. No refresh. |
| 3 | Slow, long downward pull, or a slow pull that turns fast | Indicator, then armed. The sheet does not move. | `onRefresh` runs. With `refreshCanBecomeDismiss`, a fast turn hands over to the sheet as in row 2. |
| 4 | Drag that starts mid-list, either direction | List scrolls only. At the top: platform overscroll, no indicator, no sheet movement. | Stock fling. |
| 5 | Upward fling, lift, list arrives at offset 0 | iOS bounces, Android clamps. Sheet still. Indicator hidden. | Nothing. |
| 6 | Touch the list while it is still moving from row 5 | List only. | Stock fling. |
| 7 | Pull into `sheet`, reverse upward past the start | Sheet returns to fully open, then the indicator, then the list scrolls. One gesture throughout. | Commit of whichever state is active. |
| 8 | Pull into `indicator`, reverse upward | Indicator shrinks to nothing, then the list scrolls. | Stock fling. |
| 9 | Pull down while `onRefresh` is running | Sheet follows the finger. Spinner keeps spinning and travels with the content. | Close or spring back. No second `onRefresh`. |
| 10 | Mostly horizontal swipe on the list | Nothing moves. | Nothing. |
| 11 | Arm, hold still for half a second, lift with a flick | Indicator stays armed. Sheet does not move. | `onRefresh` runs. |
| 12 | Second finger lands during a pull | Current owner keeps tracking. No takeover. | Commit when the last finger lifts. |
| 13 | Three rows instead of 30 | Rows 1, 2, 3, 7 and 9 behave the same. | Same. |
| 14 | `isScrollControlled: true` | Rows 1 to 12 behave the same. | Same. |
| 15 | Drag handle on: drag the handle | Sheet follows from the first pixel. Arbitrator overlay shows `idle`. | Stock close or spring back. |
| 16 | Drag handle on: screen reader activates the handle | Not applicable. | Sheet closes. |
| 17 | System back, barrier tap, pointer cancel mid-pull | Not applicable. | Back and barrier close. Cancel springs back and does not refresh. |
| 18 | Route opened with `enableDrag: false` | Indicator only. The sheet never moves. | Refresh or retract. |

## 8. Open questions and first slice

### Open questions

1. **Exit velocity.** The plan pops and lets the exit simulation run from the current value. Should the simulation start at the finger's release velocity? Try it once the first slice exists.
2. **`PopScope`.** Stock drag-to-close calls `Navigator.pop` directly. Should the package use `maybePop` and spring back when the pop is refused?
3. **Arrive-at-top handoff.** iOS lets a gesture that began mid-list continue into a sheet drag once the content reaches the top. The brief excludes it. It fits the model as a config flag later.
4. **Apps that pass their own `ScrollController`.** They do not inherit the package controller, so nothing is arbitrated. Options: a `controller` parameter that the package wraps, or a documented requirement to use the inherited one.
5. **`triggerMode: anywhere`.** The parameter exists on `RefreshIndicatorOpt`. Proposed meaning inside the route: an ineligible gesture may enter `indicator` on reaching the top, but never `sheet`.
6. **Refresh in flight.** Section 5.6 sends a top pull straight to the sheet. Check in testing that people who habitually re-pull are not surprised.
7. **Nested and multiple scrollables** inside one `RefreshIndicatorOpt`. The plan assumes one vertical scrollable at depth 0, as `defaultScrollNotificationPredicate` does.
8. **`createSimulation` on `ModalBottomSheetRoute`.** The hook is on `TransitionRoute` and the modal route does not override it in this SDK. Confirm with a test in slice 1 that entry and exit are visually unchanged.
9. **Sheet height.** Stock reads it from a private key. The package will read the render box of the nearest `BottomSheet` ancestor. Confirm it matches when `constraints` or a drag handle are set.

### Smallest first implementation slice

Goal: prove the two seams, with no policy.

1. `RefreshSheetRoute` with `sheetController` and the linear-plus-simulation override.
2. `_ArbitratedScrollController` and position, installed by `RefreshIndicatorOpt` through `PrimaryScrollController` when inside the route.
3. A two-target rule only: an eligible downward delta goes to the sheet; upward deltas unwind the sheet, then go to the list. Release uses `closeVelocity` and `closeProgress`. No indicator in this slice.
4. Example: push `RefreshSheetRoute` instead of calling `showModalBottomSheet`.
5. Tests: a widget test that drags the list down and reads the sheet's position after each `moveBy`; one for spring-back, one for close, one for reverse-then-scroll, one for a drag starting mid-list, each under both platform physics.

That slice already satisfies matrix rows 4, 5, 6 and the sheet half of 2 and 7.

Slice 2 adds the package-owned indicator and the full arbitrator with the config object, plus unit tests that replay recorded sample traces through `RefreshSheetArbitrator`. Slice 3 adds the overlay and sliders and runs E1 to E8.

New open question from slice 2:

10. **Slow dismiss.** With the deadline and the armed lock, only a fast pull can drag the sheet from the list. Slow users can close it with a scrim tap, system back, or the drag handle. Is that enough, or does a slow dismiss need its own affordance?

## 9. Implementation record

### What is built

| Slice | Contents | Tests |
|---|---|---|
| 1 | `RefreshSheetRoute` (linear controller plus `createSimulation`), `SheetScrollController` and position, the two-target rule, `showRefreshModalBottomSheet` | replaced by slice 2's widget tests |
| 2 | Package-owned indicator, `RefreshSheetArbitrator`, `RefreshSheetArbitrationConfig`, `[RSheet]` debug logs (`debugRefreshSheetLogs`) | `test/arbitrator_test.dart` (trace replays), `test/refresh_indicator_bottom_sheet_test.dart` (widget tests under Android and iOS physics) |
| 3 | Example app tuning screen: sheet variants (9/16 or scroll-controlled, 30 or 3 rows, drag handle, `enableDrag`), platform physics override, sliders for the hypothesis parameters, a live overlay of the arbitrator state, and per-gesture labels with copy-to-clipboard for the experiments | none; example only |

### Changes against the plan

1. **Arming locks the gesture to the indicator.** Device report: a slow pull past the arm distance that then sped up dismissed the sheet. Fix: an armed indicator never hands over.
2. **Takeover deadline.** A second device trace showed the same problem before arming: a slow pull to 74.8 px of a 122.9 px arm distance, then a flick, moved the sheet. Fix: no takeover after `takeoverDeadline` (200 ms) from pointer down.
3. **Distance gate, dwell lock and re-entry hysteresis removed.** After 1 and 2 they could no longer fire. `dismissDistanceTop`, `dismissDistanceBody`, `armedDwellLock`, `dwellSpeed` and `reentryHysteresis` are gone from the config.
4. **`refreshCanBecomeDismiss`** (default true) lifts the lock from 1 and 2 so a refresh can turn into a dismiss. With it on, the risk the dwell lock covered comes back: a lift-off flick after arming can close the sheet. Set it false to keep that lock.
5. **Config fields the plan left implicit:** `instantVelocityFactor`, `jitterFlips`, `snapDuration`, `retractDuration`.
6. **Eligibility is decided at drag start**, in `_SheetScrollPosition.drag`, not at pointer down. The position's `hold` records whether the list was at rest when the finger landed.
7. **The indicator is clipped** to the list area. It slides in from above, and without a clip it painted over the sheet's rounded top edge.
8. **iOS touch slop.** On iOS about 29 px of a slow drag goes to touch slop and the bouncing physics' motion threshold before the indicator moves. The arm distance is therefore further away in finger travel on iOS than on Android.
9. **iOS spinner.** On iOS the indicator is a `CupertinoActivityIndicator` (partially revealed while pulling, spinning while `onRefresh` runs), inside and outside the route. Other platforms keep `RefreshProgressIndicator`.
10. **Review fixes.**
    - A pointer cancel is recorded by the arbitrator from the `Listener`, because the scroll recognizer reports an accepted drag's cancel as a normal end.
    - While the route pops, the sheet's controller is never written (stock `_dismissUnderway`).
    - A close when the route is not current springs the sheet back.
    - Reversed lists and mouse drags are ineligible.
    - A drag that catches the entry animation starts idle, not in `sheet`; only a drag that catches a spring-back keeps the sheet.
    - `debugRefreshSheetLogs` defaults to false.
11. **Not done:** `triggerMode` and `notificationPredicate` are ignored inside the route (open questions 5 and 7), and the stock indicator's scale-down "done" animation is not reproduced.
12. **Flutter 3.50.** The repo pins Flutter 3.50.0 (Dart 3.14.0). The package and the example import `material_ui` and `cupertino_ui` instead of the deprecated `package:flutter/material.dart` and `package:flutter/cupertino.dart` libraries. The example Android project uses the 3.50 template toolchain: Gradle 9.5.0, Android Gradle Plugin 9.3.1, Kotlin 2.4.20.
