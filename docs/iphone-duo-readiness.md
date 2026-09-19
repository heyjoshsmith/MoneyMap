# iPhone Duo / iOS 27.1 adoption

Prepared against Xcode 27.0 (27A5209h), iOS 27.0 SDK, on September 17, 2026.
The deployment target remains iOS 26.0. This is preparation for the Duo API families,
not a claim that every unrelated iOS 27.1 framework feature belongs in MoneyMap.

## Code prepared now

- `MoneyMapWindowRoot` owns one `DeepLinkManager` per window. URLs and Spotlight
  activities go to their receiving window. `MoneyMapSceneRouter` sends notification
  routes to one active window and queues them when none is active. Closed windows
  are not retained. Pending App Intent routes are consumed on activation, not by
  arbitrary view appearances.
- `MoneyMapApp` keeps the shared model container and a stable `PaydayManager` above
  window presentation. Notification and TipKit setup runs once. The generated scene
  manifest permits multiple scenes. A typed `WindowGroup` now opens Wallet sections,
  bills, accounts, goals, and Plan through `MoneyMapOpenWindowButton`. The same
  content identity can reactivate its existing window. Actions are gated by the
  scene’s `supportsMultipleWindows` environment value.
- `SceneStorage` restores each window’s selected tab, Wallet/goal selection, compact
  column, and transaction filter choices/presentation. Only navigation identifiers
  and filter settings are stored; financial values and drafts are not serialized.
  `MoneyMapSceneRestoration` restores snapshots into live view state once, so hosted
  views and previews still work without a scene restoration store.
  Initial window content is applied once so restoration does not reopen the original
  destination after the user has navigated elsewhere.
- Transaction filters use a native inspector: a trailing column when space permits
  and a sheet in compact layouts. The same filter bindings drive both presentations.
  `InspectorCommands` supplies the standard Control-Command-I toggle for the active scene.
- Wallet and Goals use `NavigationSplitView`, stable selections, and native compact
  navigation. Detail stacks reset when selection changes, not when window size changes.
- Plan's guided flow owns its draft and current step above `MoneyMapCompanionLayout`.
  Controls and a live preview are separate scrolling panes. A narrow window keeps
  the guided flow and includes the full allocation in Review. Accessibility sizes
  use the same single-pane fallback. Resizing does not save or discard a plan.
- Primary Plan actions use native toolbars. Modal cancel/save/done actions have
  semantic placements and symbol labels. Keyboard dismissal stays in keyboard bars.
- Today, Ask, Plan's overview, and goal details have bounded reading widths. Wallet,
  planning options, and goal metrics size their grid cells with Dynamic Type. Bill
  review can scroll in short windows, and goal sheets can expand.

## Window workflows

- Use the context menu on a Wallet tile or goal row to open it in another window.
- Bill and account action menus also offer Open in New Window. Goal detail and Plan
  expose the action in their secondary toolbar actions; Wallet can open its overview.
- Reopening the same content can focus its existing window. Other windows retain
  their own navigation and filters. Closing a window does not delete financial data.
- Transaction filters can remain visible beside the list. Toggle them with the filter
  button or the standard inspector command (Control-Command-I).

## CSV drops

The CSV follow-up build and all 67 tests passed on the iOS 27.0 iPad simulator.
New tests cover file-provider URL expiration, review without inserting transactions,
cleanup after dismissal, same-named files, rejected replacement drops, and independent
window review state. `git diff --check` passed.

Drop one or more CSV files from Files into an available MoneyMap window to open the
existing card-selection and review flow. The importer still expects its existing
Apple Card CSV columns; drag and drop does not add a new statement format. Hovering
shows a temporary Review CSV target, and releasing files does not import transactions.

`MoneyMapCSVFile` uses an imported CSV `FileRepresentation` and copies the provider's
short-lived file into a unique temporary directory before returning from transfer.
`MoneyMapCSVReview` retains those copies through sheet dismissal and releases them
when review ends. File names and drop order are retained, including separate files
with the same name. Original user files are never removed. Active/dismissing reviews
reject replacement drops, and each window owns its own review state.

The Mac was still locked on this follow-up, so physical Files-to-MoneyMap dragging
and the live window checklist below remain unverified:

1. Open Wallet and Plan in separate windows; navigate and change filters independently.
2. Quit/relaunch with windows retained and verify restored tabs, selections, and filters.
   Explicitly closing a window discards its scene state; financial data should remain.
3. Open the same item again, route a notification, and remove an item shown elsewhere.
   Confirm focus/routing and the unavailable-item state in the other window.
4. Toggle the inspector with Control-Command-I in the active window.
5. Drop one and multiple supported CSVs, cancel review, and try another drop while a
   review is active. Confirm no transactions are inserted before explicit import.

## API integration map

Apple's [preparation talk](https://developer.apple.com/videos/play/tech-talks/111461/)
describes the 27.1 SDK rebuild as enabling edge-to-edge presentation and vertical
system bars. Standard navigation should do most of the work. Keep layout decisions
based on local geometry and size classes, not phone model, orientation, or main screen.

| API family | MoneyMap integration point | Next SDK step |
| --- | --- | --- |
| Native bars and adaptive tabs | `ContentView`, native `toolbar` declarations | Rebuild with 27.1; inspect vertical ordering and overflow. Existing sidebar placement is present in the installed 27.0 SDK. |
| Arrangements | `MoneyMapCompanionLayout` inside the Plan navigation stack | Replace its fallback arrangement with `ArrangementView` after checking the actual SDK declaration and availability. Keep the draft, step, and financial data outside the container. |
| Reserved regions | The companion container, custom card/grid layouts | Use geometry's `reservedRegions(kind: .division)` and `.occlusion` where manual placement needs fold/camera avoidance. Native lists and bars should retain their system handling. |
| Toolbar axis / overflow customization | Individual custom toolbar items | Audit the default representation first. Keep monetary values readable; only add explicit axis/overflow behavior when the actual control needs it. |
| Multiple scenes / scene activation | `MoneyMapWindowRoot`, `MoneyMapSceneRouter` | Typed window actions are implemented with SwiftUI `openWindow`. Verify dynamic availability on Duo; evaluate `UIWindowSceneActivationAction` for automatic hiding and activation-error handling on the outer display. |
| Hinge interaction | A future view-local visual effect | No angle-driven layout or financial state changes. Only add an effect with a clear purpose, availability handling, and Reduce Motion support. |
| Scene accessories / camera | A future capture surface, if MoneyMap gains one | No current camera session or capture UI exists. Do not add an accessory merely to show balances on the outer display. Observe availability if a capture workflow is added. |

Apple's [adaptive-layout talk](https://developer.apple.com/videos/play/tech-talks/111463/)
places arrangements inside navigation and outside scroll containers. The current Plan
composition follows that boundary. Do not move a navigation stack into an arrangement
or wrap two unrelated navigation destinations in it. Division regions become active
around the fold; occlusion regions describe obscured areas such as the camera.

Apple's [bar talk](https://developer.apple.com/videos/play/tech-talks/111462/) explains
why labeled system actions are preferable to custom bars. Inspect cancellation,
confirmation, secondary actions, and overflow together in each presentation.

Apple's [scenes talk](https://developer.apple.com/videos/play/tech-talks/111464/) separates
hinge effects from layout. `onHingeChange` is not a layout breakpoint. Scene creation
can be unavailable, and `CameraCaptureAccessory` requires an active camera experience.

## Adoption rules

1. Install the SDK and inspect its declarations before adding new API references.
   Runtime `#available` does not make an unknown symbol compile on an older SDK.
   Do not use guessed compiler-version checks, fake hinge models, or hard-coded
   Duo screen dimensions as substitutes.
2. Preserve the iOS 26 fallback and scene-local state. Keep one navigation hierarchy
   through size changes. Do not switch entire root trees on `horizontalSizeClass`.
3. Keep opaque backgrounds edge-to-edge, interactive content inside safe areas,
   and both leading and trailing insets independent. Let the system manage normal
   navigation, sheet, popover, and menu placement.
4. Replace the companion layout implementation without moving persistence, account
   refresh, financial calculations, or explanation generation into geometry/hinge callbacks.
5. Check the whole app after relinking: SDK-driven bars and safe areas affect existing
   screens even when those screens contain no new API calls.

## Verification

The final multiwindow build and all 63 tests passed on the iPad Pro 11-inch (M5)
simulator with iOS 27.0. `git diff --check` also passed.

The multiwindow follow-up adds coverage for encoded window identities, routing into
only the receiving window, and identifiers whose model was removed. Inspector captures
include the whole window and request presentation after mounting; the compact check
asserts an actual sheet controller is presented. The targeted iPhone Air simulator
inspector test passed and its sheet screenshot was reviewed. The expanded iPad inspector
was reviewed with separate Transactions and Filters toolbars.

Live creation/focusing of multiple app windows, cold-launch scene restoration, and
keyboard interaction still need interactive validation. The Mac was locked during this
work. Hosted view tests do not provide a full SwiftUI scene restoration lifecycle, so
serialization/routing coverage must not be described as a verified cold restart.


The initial preparation build and all 59 tests passed with no test failures.
Seven hosted screen renders were reviewed: Plan at compact/expanded/accessibility
sizes, and Wallet/Goals at compact and expanded sizes. Synthetic in-memory data was
used. The compact captures also verify a second incoming route while the list column
is hidden. Visual review caught and corrected the goal placeholder's sizing and
large-text Plan icon spacing.

Reproduce the build and tests with the installed toolchain:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project AddMoneyMap.xcodeproj -scheme MoneyMap -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

Screen renders are retained as attachments in the test result bundle. These are hosted
SwiftUI checks, not end-to-end touch/keyboard or physical-device testing. Interactive
simulator inspection was unavailable because the Mac was locked.

Automated coverage includes financial planning, deep links/pending routes, independent
window routing, and a hosted SwiftUI resize test that edits a draft, changes width in
both directions, and switches to accessibility text while checking state identity.

The final 27.1 validation matrix must include Today, Wallet and its destinations, Plan
and every guided step, Goals and editing sheets, Ask/search, Settings, imports, and bill
review. Exercise closed/open/partially folded poses, both rotations, narrow multitasking,
keyboard shown/hidden, large text, light/dark themes, and asymmetric safe areas. Verify:

- Selected items, drafts, current steps, focus, and scroll position survive transitions.
- All controls remain reachable and meaningful amounts remain readable.
- Two windows navigate independently; a notification opens only one destination.
- Opening/closing does not repeat account refresh or explanation generation.
- No controls straddle an active division region and none overlap camera/status UI.

The installed SDK has no Duo simulator or arrangement/region declarations. Current-SDK
tests cannot certify fold behavior, vertical bars, scene-creation availability on Duo,
or outer-display accessories. Those remain the SDK adoption gate, not implemented stubs.
