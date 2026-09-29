# Mac workspace redesign

The main window now separates Overview, Banks, and Activity with native sidebar navigation. Bank rows lead to an individual bank page; balances remain immediately visible while account enrichment and data access open on demand.

## Background service and menu bar

The app owns one sync coordinator independently of its window. A persistent MenuBarExtra uses the app icon and provides service status, the last bank update, refresh, workspace, settings, and explicit full-quit actions. Closing the main window, Command-Q, and ordinary Dock Quit move the app to accessory activation policy when Keep syncing when I close MoneyMap is enabled (default). The Dock icon returns when reopening the workspace. Menu-only state persists; `--menu-bar-only` also requests it at launch. Launch at login remains a user-controlled setting.

Quit MoneyMap Completely terminates the service. Quit events carrying a system reason are allowed through for logout/restart/shutdown. This is a resident menu bar process, not a separate daemon; force quit, sleep, logout, and shutdown stop or suspend its work. A user-requested process activity protects background work from App Nap without preventing idle system sleep.

Verification: six executable AppKit lifecycle checks cover close/quit preferences and actual accessory/regular activation policies. Signed build passed, and menu panel renders were reviewed in light and dark appearances. Native menu clicks and real OS shutdown were not exercised.

Installed runtime verification on September 19: the app reported accessory/menu bar mode at 18:33:50 EDT, then completed automatic bank refresh and iCloud upload at 18:34:30 in the same process. This confirms live bank work continues without Dock presence.

Color hierarchy uses a cool neutral page canvas, raised content surfaces, tinted account summary bands, and neutral capability sections. Violet highlights access upgrades; amber highlights broken access. Shared surface styling adapts to light/dark appearance and increased contrast. Account cards no longer depend on outlines for separation. Signed build and 12 light/dark content renders passed for this styling update; installed and launched on Mac.

Guided sheets cover initial service setup, adding a bank, reconnecting, and updating iPhone data. Setup verifies keys before saving them. Connection guides resume saved Hosted Link sessions, distinguish incomplete authorization from success, retain error details, and confirm explicit cancellation. Closing a guide leaves the saved bank session available from Overview.

Settings exposes automatic updates, launch at login, and connection setup first. Refresh schedule, advanced Plaid configuration, and troubleshooting are separate collapsed sections. Test-bank creation remains available only in the test environment. Secrets and Link tokens are not displayed in diagnostics.

Account pages now use adaptive cards with prominent balances, credit limits or available funds, and account-specific capability rows. Each capability opens a focused sheet with bank data, missing-field labels, source/check timestamps, and optional diagnostics. Only account-relevant products appear. Bank-level success alone does not mark an empty account payload available, and cached balances remain labeled as delayed.

Missing product consent offers Upgrade Data Access; known authentication failures offer Reconnect Bank. Temporary errors, unsupported products, unreported fields, and successfully checked empty activity are distinct states. Pending Mac update sessions retain an optional upgrade intent so resumed guides use the same language without changing the persisted authentication tokens. The capability and connection-intent fixture script verifies 13 scenarios. Institution product coverage also prevents offering upgrades that the bank does not support.

Verification: signed Mac build and strict signature verification passed; installed and launched on September 19, 2026. Twelve offscreen content renders covered Overview, Banks, bank details, Settings, connection preparation, and setup in light and dark appearances. Native sidebar/window chrome and interactive transitions were not verified: native UI inspection returned a closed-pipe error. Render fixtures used an isolated in-memory store and no live bank requests. Existing persisted bank data and pending authorization are preserved.
