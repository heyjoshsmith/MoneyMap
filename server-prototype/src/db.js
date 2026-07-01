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
