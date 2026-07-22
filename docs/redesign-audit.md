# MoneyMap Redesign Audit

Date: July 1, 2026
Branch: `codex/fresh-coat-redesign`

## Goal

Redesign MoneyMap so it is easier to read, calmer to use, and clearer from first launch through expert daily use without removing any existing data or app capabilities.

MoneyMap's strongest product idea is already present: it helps someone answer, "What needs my attention before my next payday, and what should I do with the money I have?" The redesign should make that idea obvious everywhere.

## Data That Must Stay

The redesign should preserve and continue to surface:

- Paydays: next payday, amount per payday, savings per paycheck, save strategy.
- Bills: name, amount, due date, paid date, status, category, recurrence, image, notes, autopay, autopay source, grace period.
- Credit cards: balance, credit limit, utilization, APR, minimum payment, statement balance, issuer, last four digits, statement closing date, promo APR expiration.
- Transactions: merchant, friendly name, category, type, amount, dates, purchaser, linked credit card, CSV import flow.
- Goals: name, target amount, deadline, weight, amount saved, amount per paycheck, image, URLs.
- Planning: paycheck recommendations, card payoff strategies, goal contribution strategies, scenarios, generated explanations.
- Activity history: bill payments, goal contributions, recommendation batches.
- System surfaces: widgets, Live Activities, notifications, App Intents, Spotlight, Siri donations, Share extension, Watch app.

## Journey Audit

### First Download

What works:

- Home already gives a reasonable setup order: set payday, add bills, add goals.
- No account wall is needed before the user can understand the app.
- The launch fix gives the app a branded first impression instead of a blank screen.

What gets in the way:

- Five tabs appear before the user knows what each one means.
- "Search" is available before there is meaningful data to search.
- "Settings" takes a permanent tab spot even though it is not a core daily job.
- "Recommendations" is one of the app's most valuable features, but it is hidden behind Home.
- "What's New" can appear before a new user understands the baseline app.

Recommendation:

- Make first launch a guided Today experience, not a general dashboard.
- Keep setup as three clear jobs: Payday, Bills, Goals.
- Delay feature education until after the user has at least one real input, unless it is needed to finish setup.

### Setup User

What works:

- Payday is correctly treated as the foundation.
- Bills and goals can be added independently.
- Credit card details support serious planning depth.

What gets in the way:

- The user is asked to understand too many concepts at once: payday, bills, credit cards, goals, recommendations, search, smart features.
- Add Bill mixes simple monthly bills with advanced credit-card planning fields.
- Required versus optional fields are not visually obvious.
- Notification settings are tucked into Pay, while the app's main promise is payday-aware reminders.

Recommendation:

- Use progressive disclosure: collect only the fields needed for the next useful answer, then invite richer details later.
- Split "Add Bill" into a simple path and a credit-card path.
- Put notification setup at the moment it creates value, such as after the first payday and bill exist.

### Daily User

What works:

- Home computes the next action and bills due before payday.
- Bills has fast swipe actions for paying and marking paid.
- Credit-card utilization and recommended payment are valuable daily signals.
- Search can find bills, goals, transactions, and planning context.

What gets in the way:

- Home, Bills, and Recommendations repeat overlapping concepts with different hierarchy.
- Money values compete with each other; the app often gives every number the same weight.
- Heavy card styling, gradients, and shadows reduce readability.
- Bills and credit cards are interleaved, but they behave differently enough to need clearer grouping.
- The most important daily question, "Am I okay until payday?" is not the dominant visual answer.

Recommendation:

- Make Today the command center: one answer, supporting evidence, then actions.
- Use semantic color only for meaning: red for overdue, orange for due soon, green for complete/on track, blue for neutral planning.
- Use compact native lists for repeatable financial data and reserve cards for summaries or individual objects.

### Paycheck Planning

What works:

- The planning engine is the strongest expert feature.
- It considers cards, goals, payday timing, strategies, and scenarios.
- Apply actions update real data and log activity.

What gets in the way:

- The feature is named "Recommendations" and lives one level down, which undersells it.
- The form is long and starts with controls instead of an answer.
- Card payments, goal contributions, scenario comparison, and Apple Intelligence all compete in one vertical list.

Recommendation:

- Promote this to a top-level Plan tab.
- Lead with a paycheck plan summary: available cash, must-cover bills, suggested card payments, suggested goals, unallocated cash.
- Move strategies and explanations behind segmented controls or detail sections.

### Bills And Cards

What works:

- The app stores rich bill and card data.
- Swipe actions make frequent work fast.
- Credit-card utilization is a strong organizing concept.
- Transactions and CSV import are meaningful power-user capabilities.

What gets in the way:

- BillsHome uses a gauge, card rows, horizontal bill cards, and detail cards with different visual rules.
- Credit card rows and bill rows do not feel like one product family.
- Detail screens use large hero imagery even when the user needs dense financial facts.
- Payment entry behavior and validation are not equally clear across every payment path.

Recommendation:

- Use two clear sections: Cards and Bills.
- Give each card/bill row a predictable structure: name, status, due date, amount, next action.
- Put transactions under a dedicated "Transactions" detail area with search/filter/sort controls.
- Keep images, notes, and advanced fields, but make them secondary to financial facts.

### Goals

What works:

- Goal cards are visual and motivating.
- Goals have enough data to support real planning: deadline, progress, amount saved, amount per paycheck, weight, image, URLs.
- Add Savings can distribute across goals.

What gets in the way:

- The visual grid is attractive but less scannable than bills.
- Add Savings is hidden in a secondary menu.
- There is no top-level summary of goal health before the card grid.
- The list view exists as a code path but is not user-selectable.

Recommendation:

- Start Goals with a summary: total saved, remaining, goals behind, next deadline.
- Offer a segmented control for Cards/List if both layouts stay.
- Make Add Savings a primary action.

### Search And Assistant

What works:

- Search spans bills, goals, transactions, and planning.
- Examples give users useful starting prompts.
- Generated answers are grounded in local app data.

What gets in the way:

- The tab says "Search," but the screen says "Search and Ask"; the product intent is split.
- Local results, generated answers, and visual summaries can feel like separate features stacked together.
- The assistant is powerful, but it does not yet feel like a command surface for the rest of the app.

Recommendation:

- Rename the tab to Ask.
- Treat Ask as the app's natural-language command center: search, explain, and route to action.
- Keep local results first and make generated answers visibly secondary when model availability is limited.

### Settings And System Features

What works:

- The app has serious system integration: widgets, Watch, notifications, Spotlight, Shortcuts, Share extension, Live Activities.
- The destructive "Remove All Data" action is confirmed.
- Activity history is available.

What gets in the way:

- Settings is too flat for the amount of trust-sensitive behavior it controls.
- "Smart Features" and "Search and Ask MoneyMap" duplicate concepts in other areas.
- Scheduled notifications are a diagnostic-style list rather than a user-centered reminder settings screen.

Recommendation:

- Move Settings out of the main tab bar and into a toolbar/profile area.
- Group settings as: Notifications, Data and Import, Activity, Smart Features, About.
- Keep destructive data removal isolated in a clearly labeled Data area.

## New Design Philosophy

### Calm Command, Progressive Detail

MoneyMap should feel like a calm financial command center. It should not try to show everything at once. It should answer the user's next money question first, then offer the supporting details and actions.

The product sentence:

> MoneyMap shows what needs attention before payday and helps you move money confidently across bills, cards, and goals.

Design principles:

- Payday is the lens. Most screens should explain how their data affects the next payday or the next pay cycle.
- Answer first, evidence second, action third. Every major screen should begin with the user's likely question and a clear answer.
- Preserve the data, simplify the surface. Rich fields stay, but advanced fields move behind detail areas.
- Use native controls over custom decoration. Lists, Forms, segmented controls, menus, sheets, gauges, and system search should do the heavy lifting.
- Treat color as meaning. Avoid decorative gradients for financial rows. Use semantic color only when it communicates state or urgency.
- Make money readable. Use monospaced digits for amounts, consistent precision, and clear labels before big numbers.
- Keep actions near the data they change. Pay, mark paid, add savings, import transactions, and apply plan should live beside the relevant object or summary.
- Ask is a power surface, not a novelty. Natural language should help find, explain, and route to existing app actions.
- Permissions are earned. Ask for notifications only after the user has created something worth reminding them about.

## Proposed Information Architecture

Recommended top-level tabs:

1. Today
   - Replaces Home.
   - Shows payday status, cash before payday, overdue/due-soon bills, goals needing attention, and one primary next action.

2. Bills
   - Contains Cards and Bills sections.
   - Keeps transactions, CSV import, payment actions, utilization, and bill detail.

3. Plan
   - Promotes Recommendations and payday planning.
   - Includes paycheck amount, strategy, suggested card payments, suggested goal contributions, scenarios, and explanations.

4. Goals
   - Keeps visual goal cards but leads with goal health and Add Savings.

5. Ask
   - Renames Search.
   - Searches local data, answers questions, and routes to bills, goals, transactions, and plans.

Settings should move to a toolbar button from Today or a More menu inside Ask/Today. It should not occupy one of the five primary daily tabs.

## Visual Direction

- Background: native grouped background.
- Content surfaces: quiet secondary grouped surfaces with 8 pt corner radius, minimal shadows.
- Typography: large titles only for screen titles; headline/subheadline for rows; monospaced digits for money.
- Row structure: icon/status, title, secondary detail, amount/action.
- Cards: summary cards only, not every row.
- Color: neutral by default; red overdue, orange due soon, green paid/on track, blue informational, purple reserved for assistant/intelligence.
- Motion: subtle transitions for applying plans, marking paid, completing setup, and moving between summary/detail.
- Accessibility: Dynamic Type, VoiceOver labels for financial summaries, contrast-safe semantic colors, reduced-motion-friendly animations.

## Implementation Phases

### Phase 1: Foundation

- Add shared design helpers for money text, section headers, summary rows, action rows, and empty states.
- Rename Home to Today and Search to Ask in the tab bar.
- Move Settings out of the tab bar.
- Keep all existing SwiftData models unchanged.

### Phase 2: Today

- Status: implemented in the current redesign branch.
- Rebuild Home around one payday-aware answer.
- Keep setup steps, overview, next action, quick actions, and due-before-payday data, but reduce duplication.
- Add clearer empty states for new users.

### Phase 3: Bills And Cards

- Redesign BillsHome into Cards and Bills sections.
- Normalize credit-card and bill row layout.
- Preserve swipe actions, payment flows, transaction import, and detail fields.

### Phase 4: Plan

- Promote Recommendations to Plan.
- Put the summary first, then strategies, then details.
- Keep Apple Intelligence explanation as an optional enhancement, not the main path.

### Phase 5: Goals

- Add a goal health summary.
- Make Add Savings primary.
- Offer card/list layout only if both remain polished.

### Phase 6: Ask And System Surfaces

- Rename and clarify Ask.
- Align widgets, Watch, Spotlight, and Shortcuts with the new Today/Plan language.
- Rework notification settings around user outcomes instead of scheduled-request diagnostics.

## Acceptance Criteria

- No existing SwiftData fields or relationships are removed.
- Existing bills, cards, transactions, goals, paydays, activity history, widgets, notifications, Spotlight, and App Intents continue to work.
- First launch explains what to do without requiring prior knowledge.
- Experienced users can answer "what needs attention before payday?" in one glance.
- Payments, goal contributions, imports, and recommendation application stay close to the data they modify.
- The app builds on the OS 27 toolchain after each phase.
- Key screens are checked with empty data and realistic populated data.
