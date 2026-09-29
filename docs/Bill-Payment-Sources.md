# Bill payment sources

Today checks upcoming, active, unpaid bills against the account or credit card assigned to each bill. It no longer subtracts every bill from one selected planning account.

Open **Today → Bill Payment Sources** to assign bills. The same **Pay From** chooser is available in bill details and the bill editor, including manual and payment-link bills. Choices use the existing `Bill.paymentMethodID` and `PaymentMethod` fields, preserving the shared store schema. Changing payment mode does not clear the source.

The chooser lists bank accounts/pockets separately, along with credit cards and saved payment methods. Linked payment history can suggest sources; it does not silently select one. Choices only describe payments in MoneyMap and do not modify bank or biller instructions.

Coverage rules:

- All bills assigned to the same underlying bank account share its available balance, even when separate debit-card/ACH method records point to it.
- A surplus in another pocket never offsets a source's shortfall.
- Credit cards use available credit, or a reported credit limit minus debt. Debt balances themselves are never treated as spendable money.
- Unassigned bills, disconnected accounts, unsupported currency, invalid amounts, and unavailable balances remain unconfirmed.
- The planning-account remainder subtracts only bills assigned to that account; other pockets and credit limits cannot inflate it.
- Balances are the latest saved bank snapshots. The feature does not forecast pending deposits, future transfers, or credit-card repayment timing.

Validation: the full simulator suite passed 161 tests, including 11 new coverage/persistence regressions. Follow-up targeted checks and a phone-width render cover the final UI. Test cases include a checking account with $100 alongside a separate funded Rent pocket, shared account reservations, isolated shortfalls, duplicate IDs, disconnected/foreign accounts, missing balances, credit capacity, and persistence of manual-payment assignments.
