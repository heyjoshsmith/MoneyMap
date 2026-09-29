# Bank data expansion

## Objective
Use the financial data available through the connected Plaid accounts throughout Mac sync, iCloud transport, and iPhone views and calculations. Preserve manual choices and existing stores. Install the Mac changes before corresponding iPhone launches.

## Implemented
- Actual credit limits; credit APR, minimum payment and statement balance integration; bank statement and payment details.
- Full credit, mortgage and student-loan metadata, with independent product freshness.
- Modern transaction categorization, merchant metadata, location, counterparties, dates and payment channel.
- Imported transaction correction, pending-to-posted replacement, removal tombstones, and source-currency retention without counting foreign amounts as dollars.
- Recurring income and payment streams, with reviewed bill/pay-plan creation.
- Investment holdings, securities and investment transactions; investment/loan-specific Mac connection entry points.
- Product availability and consent/error reporting; cached balance fallback when live Balance is unavailable.
- Mac-authoritative bank snapshots; separate iPhone review receipts prevent stale phone snapshots replacing newer Mac data.
- CloudKit assets for histories exceeding the inline payload threshold; optional additive model and wire fields preserve old data compatibility.
- Linked card payment settlement preserves the refreshed balance instead of subtracting the payment twice.
- iPhone Bank Sync > bank > Reconnect Bank requests expanded consent through a Mac-backed Hosted Link session. Keep MoneyMap open on the Mac; prepare the request, continue to the bank in Safari, then return to MoneyMap. The Mac checks completion, syncs available data, and publishes the snapshot before marking the request successful.
- Phone reconnect requests expire after 30 minutes, resume across sheet dismissal, and protect canceled/superseded requests with conditional CloudKit writes. API secrets, access tokens, and Link tokens stay on the Mac; only the short-lived Hosted Link URL travels through private iCloud. External Safari needs no new custom redirect configuration. The Watch verification gate remains unchanged.

## Verification so far
- Fixed Capital One update-mode INVALID_FIELD: reconnect resolves the linked institution through Plaid and intersects additional consent with its supported products. Unsupported investments no longer block a liabilities reconnect; banks supporting neither receive ordinary update mode with the consent field omitted. All Mac/phone/Watch API callers share this selection. 24 API fixture scenarios passed, including liabilities-only, investments-only, and neither; signed Mac build verified and installed. User retry is required to verify live authorization.
- iPhone reconnect: 4 command lifecycle/URL-safety tests passed; 21 Mac API fixtures passed, including expanded consent and external Safari request parameters. A real bank authorization through this new phone flow remains to be completed by the user.
- Reconnect update: signed Mac and iPhone builds passed. Mac installed and launched, with a successful live bank refresh and iCloud upload at 15:28 EDT. Updated iPhone app installed successfully on the physical iPhone Air.
- 59 selected iPhone simulator regression and render tests passed on 2026-09-19 (LinkedCardRefreshTests, PlaidLocalSyncImporterTests, PlaidEnrichmentTests, BankDataPresentationTests, FinancialPlanningEngineTests).
- Scripts/verify-plaid-api.sh compiled actual Mac API source and passed 18 mocked-network scenarios, including successful, incomplete and canceled update-mode Link sessions.
- Mac signed build passed; installed at /Applications/MoneyMapMac.app and launched.
- Live Mac cache migrated successfully, retained 5 connections and 14 accounts, fetched 8 recurring inflows and 29 outflows, and logged successful iCloud upload.
- Live recheck after user reconnection and Mac restart at 13:08 EDT still reports ADDITIONAL_CONSENT_REQUIRED for all five liability requests and for the investment connection. Balance and recurring products succeeded for all five connections; iCloud upload completed.
- One-time metadata backfill succeeded on the installed Mac: 2,005 transaction records now retain enrichment.
- Updated iPhone installed and launched after Mac; device-side aggregate diagnostics verified 14 accounts and 1,922 enriched imported transactions received from the Mac.
- Native render QA passed for credit, recurring and investment details in light, dark and accessibility text sizes; sample PNGs inspected.
- Corrected update-mode completion handling, then rebuilt and reinstalled Mac; user requested to test expanded consent for one bank.
- Added foreground refresh (respecting automatic sync preference) with coalescing and five-minute throttle.
- Additional targeted timestamp-migration regression passed; final signed iPhone build installed and launched. Device diagnostics verified all 4 linked cards match bank balances and timestamps.

## Remaining verification
- Chase expanded consent and live liability payloads verified. OnePay, American Express, Capital One and E*TRADE still report ADDITIONAL_CONSENT_REQUIRED; no reconnect session is pending. User must approve the expanded bank consent before remaining payloads can be verified.
- Source/flow authority audit completed in Bank-Data-Authority-Audit.md, with 74 passing regressions and 20 API fixtures. Signed Mac installed before iPhone; live phone diagnostics verified 4/4 bank balances and 2/2 available bank payment statuses. Remaining external-data verification is blocked on the other bank consents. Physical Watch runtime and visual phone-screen inspection remain unverified.

Computer-use native UI inspection is currently failing with a closed native pipe; build/launch, local snapshot inspection and tests remain available.

## Consent configuration follow-up
- Added optional Link customization name under Mac Setup > Additional Bank Data. It is persisted locally, trimmed, and sent as link_customization_name for new and update Link sessions. Blank values retain Plaid defaults.
- 20 actual-source API fixture scenarios passed, including customization encoding and preservation of additional consent products. Signed Mac build installed and launched on 2026-09-19.
- Authenticated dashboard inspection confirmed Liabilities and Investments trial access, the default Link Data Transparency section, and Chase liability support. No dashboard settings were changed. Fresh Chase update-mode consent succeeded; both card liability records were fetched.
