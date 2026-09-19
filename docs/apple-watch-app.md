# MoneyMap for Apple Watch

Branch: `codex/watch-app`. Minimum deployment: watchOS 26. The existing iPhone/watch bundle identities are preserved. Existing unrelated changes remain uncommitted.

## Experience

The independent Watch app provides Today, bills, a paycheck plan, goals, wallet, transactions, manual setup, and settings. Watch surfaces use MoneyMap's green/sage/gold/coral palette with dark warm or system surfaces. Values are large, summaries are compact, and financial changes require confirmation. Saved contributions animate goal progress; completing a goal adds a small celebration, with reduced-motion support.

Manual setup and actions work without the iPhone app. Shared records synchronize through the existing private iCloud container. The app stops at a recovery screen if durable storage cannot open; it does not accept changes into a temporary in-memory fallback. Bank snapshots retain their source timestamps.

Manual account and transaction amounts use USD, matching the transaction schema. Bank account amounts retain their own currency. Spending totals combine USD records and USD bank transactions, deduplicating imported Plaid transaction IDs; they do not perform currency conversion. Recording spending does not automatically alter a manual account balance. Recording a payment or contribution does not move real money.

## Watch surfaces

- A configurable WidgetKit widget supports circular, corner, inline, and rectangular accessory families, including the Smart Stack.
- Each instance selects content (Today, payday, bill, account, card utilization, spending, goal), an applicable entity, display mode, spending period, amount privacy, and a palette accent.
- Display options are filtered by content. Entity choices use stable IDs; removed selections show an unavailable state instead of silently selecting another account.
- A separate relevance widget suggests bills and payday around their dates, with amounts hidden. Users can disable these suggestions.
- Configurable controls open spending, payment, contribution, or wallet flows on Watch. Payment/contribution controls can select an item. Financial updates still require confirmation inside the app.
- Native Shortcuts open payday and spending. Local reminders support detail navigation and one-hour snooze. Watch reminders default off to avoid duplicating mirrored phone reminders; standalone users can enable them in Settings.
- Timelines read an atomic local snapshot shared only between the Watch app and its extension. App groups do not synchronize across devices. Foreground changes and permitted background refreshes update summaries. Refresh timing remains controlled by watchOS.

## Shared data changes

`PaySchedule` implements weekly, biweekly, twice-monthly, and monthly calendar schedules. Existing records remain biweekly. Zero represents the last day of a month. Clamped twice-monthly dates are deduplicated. Weekends and holidays do not shift paydays. The phone's schedule editor, manager, planning calculations, and countdown widget use the shared schedule.

Goal contributions and bill payments are append-only relationship records with operation IDs. Existing saved amounts/card details migrate into opening values using original attribute names. Repeated operation IDs are deduplicated when computing balances. Existing payment writers use the shared `Bill.makePayment`; additive goal writers use `Goal.addContribution`. Absolute balance adjustments remain explicit adjustments of the opening value.

Watch actions save a receipt and audit entry with the financial update. Retried receipt IDs do not reapply. Undo checks the current state against the saved result before restoring it. This guards stale edits in the local store; live multi-device CloudKit conflict behavior still needs device testing.

Appearance preferences transfer opportunistically from iPhone over WatchConnectivity. Core data and banking do not depend on that session. Standalone users can choose their theme locally.

## Mac bank helper and deployment gate

The existing MoneyMap Mac app processes private CloudKit `WatchBankCommand` requests during its refresh loop. The Mac must be running, online, signed into the same iCloud account, and configured with Plaid credentials. Requests have individual IDs, deadlines, terminal states, and persisted link-session recovery. Access tokens and Plaid secrets stay in the Mac Keychain. The Watch receives a short-lived Hosted Link URL and uses AuthenticationServices for sign-in on Watch.

**Watch-only bank sign-in is deliberately disabled until verified.** `WatchBankCompatibility.verifiedInstitutionIDs` is empty. There is no fallback to another device. Enable an institution only after its full sign-in/reconnection flow succeeds on a physical Watch. Imported account browsing and Mac refresh requests do not require an allowlist entry. Removing a bank removes the MoneyMap connection; it does not claim to revoke a bank-side authorization.

Before release, deploy the additive SwiftData CloudKit schema and the `WatchBankCommand` record type (`payload`: Bytes; queryable recordName). Test with development iCloud first; do not reset an existing store or production schema. Update all app targets together so older clients do not overwrite ledger-derived balances. Only one configured personal Mac helper should process bank-link requests.

## Validation and remaining device checks

Automated coverage includes calendar boundaries/DST, legacy schedule defaults, invalid amounts, duplicate submissions, stale undo, persisted contributions, combined ledger entries, local migration of existing goal/card values, planning regressions, and payment matching.

Verified on September 17, 2026 with Xcode beta and the installed 27.0 simulator SDKs (the Watch deployment minimum remains 26.0):

- Watch app and WidgetKit/control/relevance extension: Debug simulator build passed.
- iPhone app and dependencies: built successfully; 45 selected schedule, action, migration, planning, payment-matching, and Plaid-import tests passed.
- Mac helper: Debug build passed.
- Watch SE 3, 40 mm simulator: app installed/launched; initial onboarding and populated Today rendering inspected. [Today screenshot](watch/today-40mm.png) uses simulator-only sample data.
- Project/plist validation and `git diff --check` passed.

The shared `MoneyMapWatch` scheme runs the Watch app directly. A Debug simulator launch with `--watch-preview` supplies deterministic in-memory sample data for visual checks; this path is excluded from physical-device and Release builds.

 A simulator build/launch is not verification of live iCloud synchronization, bank authentication, notification delivery, or on-device battery behavior. The development Mac was locked during this run, preventing interactive computer-use checks.

Before enabling bank linking or distributing:

1. Exercise standalone setup and offline edits on a physical Watch, then reconnect and compare with iPhone.
2. Verify the development CloudKit schema, concurrent payments/contributions, absolute adjustments, cancellation, and Mac sleep/restart behavior.
3. Verify each approved bank's MFA/OAuth/reconnection entirely on Watch; retain the empty allowlist until this passes.
4. Inspect every widget family, configuration editor, Control Center/Ultra action, VoiceOver, larger text, Always On, and Reduce Motion on supported hardware.
5. Verify that choosing Watch reminders does not duplicate phone notifications.

No production schema, App Store submission, real banking data, or bank credentials were changed by this implementation.
