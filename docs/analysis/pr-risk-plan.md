# Ways the scrollableBuilder PR could be closed or ignored, with a plan for each

PR: `[material_ui] Let a scroll view drag a modal bottom sheet` (local commit `8bb6ae1e1`).
Target repository: flutter/packages. Issue: flutter/flutter#36283.
Written 2026-11-15. The evidence comes from closed PRs in flutter/packages and flutter/flutter, and from the repository's CI commits of 2026-11-13.

Ordered by how likely each one is to end the PR.

---

## 1. Opening a new API before the team agrees it wants one

**Risk:** #36283 is labelled `c: proposal`, `team-design` and `P2`. No Flutter team member has commented on it since 2019. A PR that adds public API to a proposal nobody has accepted is the most common reason feature PRs get closed in material_ui.

**Evidence:**
- flutter/packages#13032 (`animationBehavior`, closed 2026-11-04). elliette asked the author to open an issue first, because "we should first decide whether we want these new APIs".
- flutter/flutter#178701. Piinks closed it with "Let's move discussion into the issue".

**Plan:**
1. Post the design on #36283 before opening the PR:
   - the `scrollableBuilder` signature;
   - one sentence saying it mirrors `CupertinoSheetRoute.scrollableBuilder` (flutter/flutter#177337);
   - a short video.
2. Ask the design team directly whether they want this API on `showModalBottomSheet`.
3. Open the PR only after a team member replies, or after about 2 weeks of silence. If you open it without a reply, link the issue comment in the PR description so reviewers see that you asked.

## 2. Automation turns the PR into a draft and the no-response bot closes it

**Risk:** CI added on 2026-11-13 (commits `66784038c` and `f180b7180` in this repo) changes how external PRs are handled:
- A PR with a missing or incomplete template checklist is converted to a draft.
- A PR without a passing `cla/google` check is converted to a draft and labelled `waiting for response`.
- The no-response bot closes `waiting for response` PRs after 21 days.

**Evidence:**
- flutter/packages#13152 was auto-closed after 21 days of `waiting for response`.
- flutter/packages#12474 was marked draft for an incomplete checklist.

**Plan:**
1. Sign the CLA (https://cla.developers.google.com/) with the same email as the commit author, before you push.
2. Keep the template exactly as it is: the description paragraph, the issue paragraph and all 11 checklist items. Tick an item only when it is true.
3. If the PR still lands as a draft, fix the cause, then click **Ready for review**. That click also clears `waiting for response`, per `f180b7180`.

## 3. The PR doesn't get the issue's priority, so it sits at the bottom of the queue

**Risk:** Commit `5a7882899` copies the P0–P3 label from issues the PR *closes*, using GitHub's closing keywords. The fork PR only names the issue in backticks, and the commit says "Addresses", so the P2 label would not carry over.

**Plan:**
- In the upstream PR description, write `Fixes https://github.com/flutter/flutter/issues/36283`.
- Only use "Fixes" if the PR really resolves the issue. If the maintainers see refresh support as part of the issue, use "Part of" instead and accept losing the label.

## 4. Reviewers suspect unreviewed AI output

**Risk:** This change was written with an AI assistant. CONTRIBUTING.ai.md asks reviewers to "consider immediately closing" PRs that:
- replaced the template with generated text;
- have a description that doesn't match the diff;
- come from an author who can't discuss the code.

The template also has an AI checkbox.

**Plan:**
1. Read every line of the diff before opening the PR, especially:
   - `_BottomSheetScrollPosition.applyUserOffset` and `goBallistic`;
   - why `builder` stays non-nullable;
   - how `_findDraggableSheet` looks up the sheet.
   Make sure you could explain each one without help.
2. Write the PR description yourself, and keep it short.
3. Tick the AI box honestly ("I read the AI contribution guidelines and understand my responsibilities").
4. During review, answer comments in your own words. Never reply "addressed" unless you checked it yourself.

## 5. "Use isScrollControlled with DraggableScrollableSheet instead"

**Risk:** The `ModalBottomSheetRoute` docs already suggest that combination for sheets with a scrollable child. A reviewer may consider the problem solved already.

**Evidence:**
- The existing doc text in `bottom_sheet.dart`, which tells you to "consider setting [isScrollControlled] to true ... to have the bottom sheet be draggable".
- Long-standing problems with that workaround: #116982 (snaps to the wrong extent) and #116427 (doesn't work with slivers). #24489 was closed as a duplicate of #36283.

**Plan:**
1. Add a short "Why not DraggableScrollableSheet" paragraph to the PR description. These points still need checking:
   - The workaround resizes the sheet instead of moving it.
   - Closing needs `shouldCloseOnMinExtent` and extent tuning.
   - The sheet has to be sized as a fraction of the screen.
   - It doesn't follow the drag and fling rules that the sheet's own drag uses.
2. Check every claim on a device, and record a side-by-side video of the workaround and this PR.

## 6. "Doesn't match Material 3"

**Risk:** Design-team reviewers close features that don't fit the current Material spec.

**Evidence:** flutter/packages#12694 (`splashRadius`). QuncCccccc closed it because "this feature doesn't align with the latest" Material 3.

**Plan:**
- Cite the Material 3 bottom sheet guidance on dismissing a sheet by swiping down. Also cite how Android's Material Components `BottomSheetBehavior` behaves: it hands nested scrolling to the sheet in the same way.
- Record a video of a native Android modal sheet with a scrolling list next to this PR on the same device.

## 7. It doesn't feel right on a real device

**Risk:** The tests pass on simulated gestures only. Reviewers try sheet changes by hand and compare them with the native behavior.

**Evidence:**
- flutter/packages#12705 was approved and then closed: dkwingsmt showed on a device that "the bug still happens".
- On flutter/flutter#177337 the first review comment was about fidelity: a fling to the top "slams to a halt".

**Plan:**
1. Run the example (`show_modal_bottom_sheet.3.dart`) on a physical Android phone and an iPhone. Check:
   - a slow drag;
   - a fast fling down from the top of the list;
   - a fling from the middle of the list that reaches the top;
   - reversing direction mid-drag;
   - a list too short to scroll.
2. Fix anything that feels wrong before opening the PR.
3. Attach the videos to the PR, the way #177337 did.

## 8. Pull-to-refresh: the API silently disables it

**Risk:** Someone who puts a `RefreshIndicator` in a `scrollableBuilder` sheet loses pull-to-refresh. A reviewer may call that a trap.

Your 2026-11-14 comment on #36283 links a PoC with refresh arbitration, so reviewers may expect it here. If refresh support *is* added inside the PR, it hits the #178701 objection instead: "widgets should not have knowledge of each other".

**Plan:**
- Keep the doc line saying a `RefreshIndicator` never starts a refresh. The Cupertino sheet has the same limit.
- Before the PR, post a follow-up on #36283. Say the PR scopes refresh out on purpose, and ask whether refresh in sheets should be a separate issue covering both Material and Cupertino.
- Leave `modal-sheet-refresh-indicator` unopened until that question has an answer.

## 9. Review stalls, or you go quiet and it goes stale

**Risk:** In the last month, small material_ui PRs took 16–29 days to merge (#13449, #13267, #13266). This PR is about 570 lines and adds a feature, so expect longer.

**Evidence:** These were closed after the author or the review stopped:
- flutter/flutter#138841: the author stopped replying.
- flutter/flutter#120053: the author had no time to file issues for the edge cases.
- flutter/flutter#67515: the PR waited a year, and the author had moved on.
- flutter/packages#13152: auto-closed after 21 days.

**Plan:**
- Set a reminder to reply to every review comment within a few days, and always within 21 days.
- If nobody reviews it within 2 weeks, ask once in Discord `#hackers-design`. Don't ping people on GitHub over and over.
- If you need a break, say so in a comment so the bot doesn't close the PR.

## 10. Too big, or bundled with other work

**Risk:** Big PRs get split or stall.

**Evidence:**
- flutter/flutter#183282: victorsanni asked for the RefreshIndicator refactor to be split, and closed it, because "each fix needs its own tests".
- flutter/flutter#94972 had to be split before review.

**Plan:**
- Upstream, this PR stays alone: no RefreshIndicator change, and no persistent-sheet (`showBottomSheet`) support.
- In the description, list each behavior next to the test that covers it, the way #120053's reviewers asked:
  - drag follows the finger;
  - spring back above half;
  - close below half;
  - fling closes;
  - reversing returns the sheet, then scrolls;
  - a drag from mid-list reaches the top, then drags the sheet;
  - a short list still drags;
  - a reversed list doesn't drag;
  - `enableDrag: false` keeps the list's normal physics;
  - the list's own controller doesn't drag the sheet;
  - works on all platforms;
  - the exactly-one-builder assert.

## 11. API objections: builder becomes optional, or the code duplicates Cupertino

**Risk:** Two objections are likely:
- Making `builder` optional turns a compile-time error, giving neither builder, into a runtime assert.
- `_BottomSheetScrollPosition` is a modified copy of `_CupertinoSheetScrollPosition`, and a reviewer may ask for one shared implementation.

**Plan:**
- **Optional builder:** point to `CupertinoSheetRoute`, which made the same trade-off. Note that the route's `builder` field keeps its non-nullable type, so no caller or subclass breaks. Offer a separate constructor, such as `ModalBottomSheetRoute.scrollable`, if they prefer compile-time safety.
- **Duplication:** explain that the two packages can only share code through public API. Offer a follow-up that adds a shared primitive in the framework's widgets layer, where `DraggableScrollableSheet` already has a similar position.

## 12. A competing PR

**Risk:** The same issue gets fixed somewhere else first, and yours is closed as a duplicate.

**Evidence:** flutter/packages#12474 was closed in favor of flutter/flutter#190911, which fixed the same issue in a more complete way.

**Plan:** Right before opening the PR, search both repositories for open PRs that mention 36283, "bottom sheet", "scrollable" or "drag". If one exists, comment there and compare the two instead of opening a second PR.

---

## Order of work

1. Device check and videos (§7, §6, §5).
2. Post the design and the refresh scope on #36283 (§1, §8).
3. Sign the CLA (§2).
4. Read the whole diff yourself (§4).
5. Search for competing PRs (§12).
6. Open the PR:
   - full template;
   - `Fixes <issue URL>`;
   - the "why not DraggableScrollableSheet" paragraph;
   - the behavior-to-test list;
   - the videos.
   (§2, §3, §5, §10)
7. Reply within days, ask for review once after 2 weeks, and never go silent for 21 days (§9).
