import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {
  createImportRecord,
  hasImportedFile,
  insertTransaction
} from './db.js';

const rootDir = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
export const inboxDir = path.join(rootDir, 'inbox');
export const processedDir = path.join(rootDir, 'processed');

fs.mkdirSync(inboxDir, { recursive: true });
fs.mkdirSync(processedDir, { recursive: true });

export function processExistingFiles() {
  const files = fs.readdirSync(inboxDir).filter((file) => file.endsWith('.csv'));
  for (const file of files) {
    importCsvFile(path.join(inboxDir, file));
  }
}

export function watchInbox() {
  fs.watch(inboxDir, (eventType, fileName) => {
    if (!fileName || !fileName.endsWith('.csv') || eventType !== 'rename') {
      return;
    }

    const fullPath = path.join(inboxDir, fileName);

    setTimeout(() => {
      if (fs.existsSync(fullPath)) {
        importCsvFile(fullPath);
      }
    }, 250);
  });
}

export function importCsvFile(filePath) {
  const fileName = path.basename(filePath);

  if (hasImportedFile(fileName)) {
    moveToProcessed(filePath, fileName);
    return { fileName, imported: 0, skipped: true };
  }

  const content = fs.readFileSync(filePath, 'utf8');
  const rows = parseCsvRows(content);

  if (rows.length < 2) {
    moveToProcessed(filePath, fileName);
    return { fileName, imported: 0, skipped: true };
  }

  const header = rows[0].map(sanitizeField);
  const dataRows = rows.slice(1);
  const { id: importId } = createImportRecord(fileName, dataRows.length);

  let importedCount = 0;

  for (const row of dataRows) {
    if (row.length !== header.length) {
      continue;
    }

    const record = Object.fromEntries(header.map((key, index) => [key, sanitizeField(row[index])]));
    const transaction = normalizeTransaction(record);

    if (!transaction) {
      continue;
    }

    const result = insertTransaction(importId, transaction);
    if (result.changes > 0) {
      importedCount += 1;
    }
  }

  moveToProcessed(filePath, fileName);
  return { fileName, imported: importedCount, skipped: false };
}

function moveToProcessed(filePath, fileName) {
  const destination = path.join(processedDir, `${Date.now()}-${fileName}`);
  if (fs.existsSync(filePath)) {
    fs.renameSync(filePath, destination);
  }
}

function normalizeTransaction(record) {
  const amountText = record['Amount (USD)'];
  const amountUSD = amountText ? Number(amountText) : null;

  if (!Number.isFinite(amountUSD)) {
    return null;
  }

  const transaction = {
    transactionDate: record['Transaction Date'] || null,
    clearingDate: record['Clearing Date'] || null,
    description: record['Description'] || null,
    merchant: record['Merchant'] || null,
    category: record['Category'] || null,
    type: record['Type'] || null,
    amountUSD,
    purchasedBy: record['Purchased By'] || null
  };

  transaction.signature = createSignature(transaction);
  return transaction;
}

function createSignature(transaction) {
  return crypto
    .createHash('sha256')
    .update([
      transaction.transactionDate,
      transaction.clearingDate,
      transaction.description,
      transaction.merchant,
      transaction.category,
      transaction.type,
      transaction.amountUSD,
      transaction.purchasedBy
    ].join('|'))
    .digest('hex');
}

function sanitizeField(value) {
  return value.replaceAll('\uFEFF', '').trim();
}

function parseCsvRows(input) {
  const rows = [];
  let row = [];
  let field = '';
  let insideQuotes = false;

  for (let index = 0; index < input.length; index += 1) {
    const char = input[index];
    const next = input[index + 1];

    if (char === '"') {
      if (insideQuotes && next === '"') {
        field += '"';
        index += 1;
      } else {
        insideQuotes = !insideQuotes;
      }
      continue;
    }

    if (char === ',' && !insideQuotes) {
      row.push(field);
      field = '';
      continue;
    }

    if ((char === '\n' || char === '\r') && !insideQuotes) {
      row.push(field);
      const cleaned = row.map((item) => item.trim());
      if (cleaned.some(Boolean)) {
        rows.push(cleaned);
      }
      row = [];
      field = '';

      if (char === '\r' && next === '\n') {
        index += 1;
      }
      continue;
    }

    field += char;
  }

  if (field.length > 0 || row.length > 0) {
    row.push(field);
    const cleaned = row.map((item) => item.trim());
    if (cleaned.some(Boolean)) {
      rows.push(cleaned);
    }
  }

  return rows;
}
