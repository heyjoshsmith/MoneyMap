import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';

const rootDir = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const dataDir = path.join(rootDir, 'data');
const dbPath = path.join(dataDir, 'moneymap-prototype.sqlite');

fs.mkdirSync(dataDir, { recursive: true });

const db = new DatabaseSync(dbPath);

db.exec(`
  CREATE TABLE IF NOT EXISTS imports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_name TEXT NOT NULL UNIQUE,
    imported_at TEXT NOT NULL,
    row_count INTEGER NOT NULL
  );
`);

db.exec(`
  CREATE TABLE IF NOT EXISTS transactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    import_id INTEGER NOT NULL,
    transaction_date TEXT,
    clearing_date TEXT,
    description TEXT,
    merchant TEXT,
    category TEXT,
    type TEXT,
    amount_usd REAL,
    purchased_by TEXT,
    signature TEXT NOT NULL UNIQUE,
    created_at TEXT NOT NULL,
    FOREIGN KEY(import_id) REFERENCES imports(id)
  );
`);

db.exec(`
  CREATE TABLE IF NOT EXISTS plaid_link_sessions (
    link_token TEXT PRIMARY KEY,
    hosted_link_url TEXT,
    created_at TEXT NOT NULL,
    exchanged_at TEXT,
    status TEXT NOT NULL,
    request_id TEXT,
    raw_json TEXT
  );
`);

db.exec(`
  CREATE TABLE IF NOT EXISTS plaid_items (
    item_id TEXT PRIMARY KEY,
    access_token TEXT NOT NULL,
    institution_id TEXT,
    institution_name TEXT,
    transactions_cursor TEXT,
    status TEXT NOT NULL,
    error_message TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    last_sync_at TEXT
  );
`);

db.exec(`
  CREATE TABLE IF NOT EXISTS plaid_accounts (
    account_id TEXT PRIMARY KEY,
    item_id TEXT NOT NULL,
    institution_name TEXT,
    name TEXT,
    official_name TEXT,
    mask TEXT,
    type TEXT,
    subtype TEXT,
    current_balance REAL,
    available_balance REAL,
    iso_currency_code TEXT,
    unofficial_currency_code TEXT,
    updated_at TEXT NOT NULL,
    raw_json TEXT,
    FOREIGN KEY(item_id) REFERENCES plaid_items(item_id)
  );
`);

db.exec(`
  CREATE TABLE IF NOT EXISTS plaid_transactions (
    transaction_id TEXT PRIMARY KEY,
    item_id TEXT NOT NULL,
    account_id TEXT NOT NULL,
    pending_transaction_id TEXT,
    transaction_date TEXT,
    authorized_date TEXT,
    name TEXT,
    merchant_name TEXT,
    category TEXT,
    amount REAL,
    pending INTEGER NOT NULL DEFAULT 0,
    payment_channel TEXT,
    iso_currency_code TEXT,
    unofficial_currency_code TEXT,
    removed INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL,
    raw_json TEXT,
    FOREIGN KEY(item_id) REFERENCES plaid_items(item_id)
  );
`);

db.exec(`
  CREATE TABLE IF NOT EXISTS plaid_liabilities (
    liability_id TEXT PRIMARY KEY,
    item_id TEXT NOT NULL,
    account_id TEXT NOT NULL,
    type TEXT NOT NULL,
    current_balance REAL,
    credit_limit REAL,
    minimum_payment_amount REAL,
    next_payment_due_date TEXT,
    last_statement_balance REAL,
    last_statement_issue_date TEXT,
    apr_percentage REAL,
    raw_json TEXT,
    updated_at TEXT NOT NULL,
    FOREIGN KEY(item_id) REFERENCES plaid_items(item_id)
  );
`);

export function hasImportedFile(fileName) {
  const row = db.prepare('SELECT id FROM imports WHERE file_name = ?').get(fileName);
  return Boolean(row);
}

export function createImportRecord(fileName, rowCount) {
  const importedAt = new Date().toISOString();
  const result = db
    .prepare('INSERT INTO imports (file_name, imported_at, row_count) VALUES (?, ?, ?)')
    .run(fileName, importedAt, rowCount);

  return {
    id: Number(result.lastInsertRowid),
    importedAt
  };
}

export function insertTransaction(importId, transaction) {
  return db.prepare(`
    INSERT OR IGNORE INTO transactions (
      import_id,
      transaction_date,
      clearing_date,
      description,
      merchant,
      category,
      type,
      amount_usd,
      purchased_by,
      signature,
      created_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    importId,
    transaction.transactionDate,
    transaction.clearingDate,
    transaction.description,
    transaction.merchant,
    transaction.category,
    transaction.type,
    transaction.amountUSD,
    transaction.purchasedBy,
    transaction.signature,
    new Date().toISOString()
  );
}

export function getSummary() {
  const totals = db.prepare(`
    SELECT
      COUNT(*) AS transactionCount,
      ROUND(COALESCE(SUM(amount_usd), 0), 2) AS totalAmount
    FROM transactions
  `).get();

  const topMerchants = db.prepare(`
    SELECT
      COALESCE(NULLIF(merchant, ''), 'Unknown') AS merchant,
      COUNT(*) AS transactionCount,
      ROUND(COALESCE(SUM(amount_usd), 0), 2) AS totalAmount
    FROM transactions
    GROUP BY merchant
    ORDER BY totalAmount DESC
    LIMIT 5
  `).all();

  const recentImports = db.prepare(`
    SELECT file_name AS fileName, imported_at AS importedAt, row_count AS rowCount
    FROM imports
    ORDER BY id DESC
    LIMIT 10
  `).all();

  return {
    transactionCount: totals.transactionCount ?? 0,
    totalAmount: totals.totalAmount ?? 0,
    topMerchants,
    recentImports
  };
}

export function getImports() {
  return db.prepare(`
    SELECT id, file_name AS fileName, imported_at AS importedAt, row_count AS rowCount
    FROM imports
    ORDER BY id DESC
  `).all();
}

export function getTransactions(limit = 50) {
  return db.prepare(`
    SELECT
      id,
      transaction_date AS transactionDate,
      clearing_date AS clearingDate,
      description,
      merchant,
      category,
      type,
      amount_usd AS amountUSD,
      purchased_by AS purchasedBy,
      created_at AS createdAt
    FROM transactions
    ORDER BY id DESC
    LIMIT ?
  `).all(limit);
}

export function storePlaidLinkSession(session) {
  const now = new Date().toISOString();
  db.prepare(`
    INSERT INTO plaid_link_sessions (
      link_token,
      hosted_link_url,
      created_at,
      status,
      request_id,
      raw_json
    ) VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(link_token) DO UPDATE SET
      hosted_link_url = excluded.hosted_link_url,
      status = excluded.status,
      request_id = excluded.request_id,
      raw_json = excluded.raw_json
  `).run(
    session.linkToken,
    session.hostedLinkUrl ?? null,
    now,
    session.status ?? 'created',
    session.requestId ?? null,
    JSON.stringify(session.raw ?? {})
  );
}

export function markPlaidLinkSessionExchanged(linkToken) {
  db.prepare(`
    UPDATE plaid_link_sessions
    SET exchanged_at = ?, status = ?
    WHERE link_token = ?
  `).run(new Date().toISOString(), 'exchanged', linkToken);
}

export function upsertPlaidItem(item) {
  const now = new Date().toISOString();
  db.prepare(`
    INSERT INTO plaid_items (
      item_id,
      access_token,
      institution_id,
      institution_name,
      transactions_cursor,
      status,
      error_message,
      created_at,
      updated_at,
      last_sync_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(item_id) DO UPDATE SET
      access_token = excluded.access_token,
      institution_id = COALESCE(excluded.institution_id, plaid_items.institution_id),
      institution_name = COALESCE(excluded.institution_name, plaid_items.institution_name),
      transactions_cursor = COALESCE(excluded.transactions_cursor, plaid_items.transactions_cursor),
      status = excluded.status,
      error_message = excluded.error_message,
      updated_at = excluded.updated_at,
      last_sync_at = COALESCE(excluded.last_sync_at, plaid_items.last_sync_at)
  `).run(
    item.itemId,
    item.accessToken,
    item.institutionId ?? null,
    item.institutionName ?? null,
    item.transactionsCursor ?? null,
    item.status ?? 'connected',
    item.errorMessage ?? null,
    now,
    now,
    item.lastSyncAt ?? null
  );
}

export function updatePlaidItemSyncState(itemId, { cursor, status = 'synced', errorMessage = null } = {}) {
  db.prepare(`
    UPDATE plaid_items
    SET transactions_cursor = COALESCE(?, transactions_cursor),
        status = ?,
        error_message = ?,
        updated_at = ?,
        last_sync_at = ?
    WHERE item_id = ?
  `).run(
    cursor ?? null,
    status,
    errorMessage,
    new Date().toISOString(),
    status === 'synced' ? new Date().toISOString() : null,
    itemId
  );
}

export function getPlaidItems() {
  return db.prepare(`
    SELECT
      item_id AS itemId,
      access_token AS accessToken,
      institution_id AS institutionId,
      institution_name AS institutionName,
      transactions_cursor AS transactionsCursor,
      status,
      error_message AS errorMessage,
      created_at AS createdAt,
      updated_at AS updatedAt,
      last_sync_at AS lastSyncAt
    FROM plaid_items
    ORDER BY created_at DESC
  `).all();
}

export function getPlaidConnections() {
  return getPlaidItems().map(({ accessToken, ...item }) => item);
}

export function upsertPlaidAccounts(item, accounts) {
  const statement = db.prepare(`
    INSERT INTO plaid_accounts (
      account_id,
      item_id,
      institution_name,
      name,
      official_name,
      mask,
      type,
      subtype,
      current_balance,
      available_balance,
      iso_currency_code,
      unofficial_currency_code,
      updated_at,
      raw_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(account_id) DO UPDATE SET
      item_id = excluded.item_id,
      institution_name = excluded.institution_name,
      name = excluded.name,
      official_name = excluded.official_name,
      mask = excluded.mask,
      type = excluded.type,
      subtype = excluded.subtype,
      current_balance = excluded.current_balance,
      available_balance = excluded.available_balance,
      iso_currency_code = excluded.iso_currency_code,
      unofficial_currency_code = excluded.unofficial_currency_code,
      updated_at = excluded.updated_at,
      raw_json = excluded.raw_json
  `);

  const now = new Date().toISOString();
  for (const account of accounts) {
    statement.run(
      account.account_id,
      item.itemId,
      item.institutionName ?? null,
      account.name ?? null,
      account.official_name ?? null,
      account.mask ?? null,
      account.type ?? null,
      account.subtype ?? null,
      account.balances?.current ?? null,
      account.balances?.available ?? null,
      account.balances?.iso_currency_code ?? null,
      account.balances?.unofficial_currency_code ?? null,
      now,
      JSON.stringify(account)
    );
  }
}

export function upsertPlaidTransactions(itemId, transactions) {
  const statement = db.prepare(`
    INSERT INTO plaid_transactions (
      transaction_id,
      item_id,
      account_id,
      pending_transaction_id,
      transaction_date,
      authorized_date,
      name,
      merchant_name,
      category,
      amount,
      pending,
      payment_channel,
      iso_currency_code,
      unofficial_currency_code,
      removed,
      updated_at,
      raw_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
    ON CONFLICT(transaction_id) DO UPDATE SET
      account_id = excluded.account_id,
      pending_transaction_id = excluded.pending_transaction_id,
      transaction_date = excluded.transaction_date,
      authorized_date = excluded.authorized_date,
      name = excluded.name,
      merchant_name = excluded.merchant_name,
      category = excluded.category,
      amount = excluded.amount,
      pending = excluded.pending,
      payment_channel = excluded.payment_channel,
      iso_currency_code = excluded.iso_currency_code,
      unofficial_currency_code = excluded.unofficial_currency_code,
      removed = 0,
      updated_at = excluded.updated_at,
      raw_json = excluded.raw_json
  `);

  const now = new Date().toISOString();
  for (const transaction of transactions) {
    statement.run(
      transaction.transaction_id,
      itemId,
      transaction.account_id,
      transaction.pending_transaction_id ?? null,
      transaction.date ?? null,
      transaction.authorized_date ?? null,
      transaction.name ?? null,
      transaction.merchant_name ?? null,
      Array.isArray(transaction.category) ? transaction.category.join(' > ') : null,
      transaction.amount ?? null,
      transaction.pending ? 1 : 0,
      transaction.payment_channel ?? null,
      transaction.iso_currency_code ?? null,
      transaction.unofficial_currency_code ?? null,
      now,
      JSON.stringify(transaction)
    );
  }
}

export function markPlaidTransactionsRemoved(transactions) {
  const statement = db.prepare(`
    UPDATE plaid_transactions
    SET removed = 1,
        updated_at = ?
    WHERE transaction_id = ?
  `);
  const now = new Date().toISOString();
  for (const transaction of transactions) {
    statement.run(now, transaction.transaction_id);
  }
}

export function replacePlaidLiabilities(itemId, liabilities) {
  db.prepare('DELETE FROM plaid_liabilities WHERE item_id = ?').run(itemId);

  const statement = db.prepare(`
    INSERT INTO plaid_liabilities (
      liability_id,
      item_id,
      account_id,
      type,
      current_balance,
      credit_limit,
      minimum_payment_amount,
      next_payment_due_date,
      last_statement_balance,
      last_statement_issue_date,
      apr_percentage,
      raw_json,
      updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  const now = new Date().toISOString();
  for (const liability of liabilities) {
    statement.run(
      `${liability.type}:${liability.account_id}`,
      itemId,
      liability.account_id,
      liability.type,
      liability.current_balance ?? null,
      liability.credit_limit ?? null,
      liability.minimum_payment_amount ?? liability.minimum_payment ?? null,
      liability.next_payment_due_date ?? null,
      liability.last_statement_balance ?? null,
      liability.last_statement_issue_date ?? null,
      liability.apr_percentage ?? null,
      JSON.stringify(liability.raw ?? liability),
      now
    );
  }
}

export function getPlaidAccounts() {
  return db.prepare(`
    SELECT
      account_id AS accountId,
      item_id AS itemId,
      institution_name AS institutionName,
      name,
      official_name AS officialName,
      mask,
      type,
      subtype,
      current_balance AS currentBalance,
      available_balance AS availableBalance,
      COALESCE(iso_currency_code, unofficial_currency_code) AS currencyCode,
      updated_at AS updatedAt
    FROM plaid_accounts
    ORDER BY institution_name, name
  `).all();
}

export function getPlaidTransactions(limit = 200) {
  return db.prepare(`
    SELECT
      transaction_id AS transactionId,
      item_id AS itemId,
      account_id AS accountId,
      pending_transaction_id AS pendingTransactionId,
      transaction_date AS date,
      authorized_date AS authorizedDate,
      name,
      merchant_name AS merchantName,
      category,
      amount,
      pending,
      payment_channel AS paymentChannel,
      COALESCE(iso_currency_code, unofficial_currency_code) AS currencyCode,
      updated_at AS updatedAt
    FROM plaid_transactions
    WHERE removed = 0
    ORDER BY transaction_date DESC, transaction_id DESC
    LIMIT ?
  `).all(limit).map(row => ({
    ...row,
    pending: Boolean(row.pending)
  }));
}

export function getPlaidLiabilities() {
  return db.prepare(`
    SELECT
      liability_id AS liabilityId,
      item_id AS itemId,
      account_id AS accountId,
      type,
      current_balance AS currentBalance,
      credit_limit AS creditLimit,
      minimum_payment_amount AS minimumPaymentAmount,
      next_payment_due_date AS nextPaymentDueDate,
      last_statement_balance AS lastStatementBalance,
      last_statement_issue_date AS lastStatementIssueDate,
      apr_percentage AS aprPercentage,
      updated_at AS updatedAt
    FROM plaid_liabilities
    ORDER BY type, account_id
  `).all();
}

export function getPlaidSnapshot(limit = 200) {
  return {
    connections: getPlaidConnections(),
    accounts: getPlaidAccounts(),
    transactions: getPlaidTransactions(limit),
    liabilities: getPlaidLiabilities()
  };
}
