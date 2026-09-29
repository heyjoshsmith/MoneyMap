# MoneyMap performance and accuracy audit — September 29, 2026

## Scope

Reviewed the current worktree, including its existing bank-data authority changes. The source scan covered app startup, Today, Wallet and transaction search, Bills and transaction details, Plan, Goals, CSV import, bank synchronization, notifications, Spotlight, widgets, Watch finance, and the Mac bank-sync service. Pattern scans covered 147 Swift files across the app and companion targets; deeper inspection focused on main-thread fetches, repeated array processing, cache invalidation, and reconciliation correctness. This is a source audit with automated and sampled physical-device validation, not a claim that every interaction has been profiled.

## Corrections

- Bank import: replace the per-review-item scan of all existing transactions with an account-scoped reverse lookup for pending-to-posted replacements. Maintain that lookup as rows change. Preserve idempotence, tombstones, and user annotations.
- Bill status refresh: prepare payment eligibility, dates, and relationship IDs once per batch. Use one-pass newest-payment selection and calendar-correct exclusive day boundaries. Preserve priority for direct links and exclude removed/pending transactions.
- Transaction search: filter before sorting; count, emptiness, and selection operations no longer sort transaction history.
- Spotlight: process transaction indexing in cancellable batches of 100, waiting for each index submission before continuing. Both full-history callers use the same scope.
- Sync diagnostics: use a store count query instead of materializing every transaction to count enrichment.
- Wallet and system integrations: refresh cached summaries and search/notification work after bank changes even when row counts are unchanged.
- Planning: avoid opening the bank store in manual-cash mode; exclude disconnected accounts when connection records exist; tolerate duplicate account/model IDs in planning and settlement lookups.
- Recurring review: read Bills transactions newest-first before applying the existing recent-history limit.
- Test/preview stores: explicitly isolate in-memory configurations from CloudKit and give them unique names. The original fixtures crashed with `No eligible connection available`; corrected fixtures exercise saves successfully.

## Validation

- Final full iOS simulator suite: **150 passed, 0 failed, 0 skipped**. `xcodebuild` exited successfully and `/tmp/MoneyMap-PerformanceAudit-final.xcresult` independently reports Passed. A 32-bill/3,432-payment batch test completed in 61 ms.
- Synthetic bank import: 2,000 rows plus idempotent replay completed in 0.48 seconds in the final simulator run. This is a Debug simulator observation, not a phone performance guarantee.
- Signed iPhone build and installation succeeded on Josh’s iPhone Air. Launch and a subsequent process listing confirmed the app running.
- Signed Mac build succeeded. Companion Watch and widget targets compiled as part of the iPhone build.
- Mac account capabilities: 13 checks passed. Mac Plaid API: 24 intercepted-network scenarios passed; these do not claim live bank API coverage.
- Live bank diagnostic snapshot reported all 4 comparable linked-card balances and all 3 bank payment statuses matching their snapshots; there were no transaction changes in that sync.
- Physical-device transaction-detail work measured 2–25 ms; recurring detection measured about 38–64 ms over 2,557 recent transactions. Plan account fetches measured 0–2 ms.
- Final physical-device Bills system-integration work measured **64 ms**, versus **259–301 ms** in the first build during this audit, with the same 32 bills and 3,426 transactions. These are sampled timings, not controlled benchmark averages. Final installation path and process listing confirmed the replacement build running.

## Evidence and limits

Local logs and result bundles are under `/tmp/MoneyMap-Performance*`. These may be removed by macOS. Device diagnostics contain private local data and are intentionally not committed. The app retains its own timing instrumentation for future comparisons.

Instruments attachment could not resolve the app process; an all-process recording ended after 2.26 seconds when the Instruments connection disconnected. No full Instruments profile or frame-rate claim is made. Recurring detection remains a short synchronous operation. Background scheduling and future CloudKit/bank delivery remain dependent on the OS and external services. The initial corrected test runner completed its tests but did not finalize its result bundle before it was stopped to validate the subsequent optimization. The final test run disabled verbose failure diagnostics and finalized successfully. Rendering tests report SceneStorage warnings from their synthetic hosting environment; these are not observed app crashes.
