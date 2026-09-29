# Bank data authority audit

Scope: Mac acquisition, iCloud snapshot transport, card balances and liabilities, transaction reconciliation, manual editing and undo, payoff planning, iPhone UI, widgets, Watch, notifications, Siri, and Spotlight.

## Ownership
- Plaid supplies account balances, credit limits, APR, minimums, statement information, transaction amounts/currency/pending/removal facts, and reported payment status/due dates.
- Manual names, categories on transactions, payment plans, schedules, notes, review decisions, and lifecycle choices remain user-owned. Planning dates are not substituted for fresh bank due dates in payment status displays.
- Missing or stale liability facts use the existing local fallback; a new balance fetch does not make older liability facts fresh.

## Repairs
- Fresh liability status takes priority over overdue inferred from a local schedule, including Chase reporting is_overdue=false with a future due date.
- An additive optional bank balance preserves the actual bank amount across local payment entries, edits and undo. Existing persisted property names remain unchanged.
- Linked bank facts are read-only in card editors and balance/limit shortcuts. Manual cards retain editing.
- Sorting, status displays, due dates, reminders, widgets, Watch, Siri and Spotlight use bank-aware projections.
- Payoff calculations use an authoritative current balance even when zero or negative; an old statement or manual planned amount cannot inflate it.
- Out-of-order iCloud downloads cannot restore older bank facts or removed accounts. User review decisions are merged separately from bank facts.
- Cached Balance fallback retains the prior live limit; failed liabilities requests retain prior suggestions.
- Payment matching requires target/payment evidence and cannot reuse a transaction, treat a refund as a payment, or count a removed record.
- Pending transactions replaced by posted transactions remain superseded on replay. Distinct bank IDs are not discarded because a manual entry happens to have the same date/amount/merchant.
- Older legacy API responses do not overwrite newer account facts.

## Verification
74 focused regression tests passed, covering linked refresh, transaction import, planning/payment matching, bank-aware presentation and cloud authority. All 20 Mac API fixture scenarios passed. Both signed Mac and iPhone builds passed. The Mac was installed first, restarted, and logged a successful bank refresh and iCloud upload. The iPhone was installed and launched; device diagnostics confirmed all 4 linked balances/timestamps match bank snapshots and both cards with bank-reported payment statuses match those statuses. Chase reports is_overdue=false with due dates October 1 and October 2, 2026.

The simulator crash reports supplied during verification came from test-store save/fetch failures. Test containers are now retained and explicitly configured without CloudKit; the final 74-test run completed without crashes. Physical Watch runtime and visual phone-screen inspection were not performed.
