import {
  getPlaidItems,
  getPlaidSnapshot,
  markPlaidLinkSessionExchanged,
  markPlaidTransactionsRemoved,
  replacePlaidLiabilities,
  storePlaidLinkSession,
  updatePlaidItemSyncState,
  upsertPlaidAccounts,
  upsertPlaidItem,
  upsertPlaidTransactions
} from './db.js';

const plaidHosts = {
  sandbox: 'https://sandbox.plaid.com',
  development: 'https://development.plaid.com',
  production: 'https://production.plaid.com'
};

export function plaidConfigStatus() {
  return {
    configured: Boolean(process.env.PLAID_CLIENT_ID && process.env.PLAID_SECRET),
    environment: process.env.PLAID_ENV || 'sandbox',
    hasClientID: Boolean(process.env.PLAID_CLIENT_ID),
    hasSecret: Boolean(process.env.PLAID_SECRET)
  };
}

export async function createHostedLinkToken() {
  assertConfigured();

  const response = await plaidPost('/link/token/create', {
    client_name: process.env.PLAID_CLIENT_NAME || 'MoneyMap',
    country_codes: (process.env.PLAID_COUNTRY_CODES || 'US').split(',').map(value => value.trim()),
    language: process.env.PLAID_LANGUAGE || 'en',
    products: ['transactions', 'liabilities'],
    webhook: process.env.PLAID_WEBHOOK_URL || undefined,
    user: {
      client_user_id: process.env.PLAID_CLIENT_USER_ID || 'moneymap-local-user'
    },
    transactions: {
      days_requested: Number(process.env.PLAID_TRANSACTION_DAYS || 730)
    },
    redirect_uri: process.env.PLAID_REDIRECT_URI || undefined,
    hosted_link: {
      completion_redirect_uri: process.env.PLAID_COMPLETION_REDIRECT_URI || 'moneymap://plaid-hosted-link-complete',
      is_mobile_app: true
    }
  });

  const linkToken = response.link_token;
  const hostedLinkUrl = response.hosted_link_url || response.hosted_link?.link_url || response.hosted_link?.url;

  if (!linkToken || !hostedLinkUrl) {
    throw new Error('Plaid did not return a hosted Link URL. Check whether Hosted Link is enabled for this Plaid app.');
  }

  storePlaidLinkSession({
    linkToken,
    hostedLinkUrl,
    status: 'created',
    requestId: response.request_id,
    raw: response
  });

  return {
    linkToken,
    hostedLinkUrl,
    expiration: response.expiration,
    requestId: response.request_id
  };
}

export async function completeHostedLink(linkToken) {
  assertConfigured();

  const tokenDetails = await plaidPost('/link/token/get', { link_token: linkToken });
  const publicToken = extractPublicToken(tokenDetails);

  if (!publicToken) {
    throw new Error('Plaid Hosted Link has not produced a public token yet. Finish the Link flow and try again.');
  }

  const exchange = await exchangePublicToken(publicToken, tokenDetails);
  markPlaidLinkSessionExchanged(linkToken);
  return exchange;
}

export async function createSandboxConnection() {
  assertConfigured();

  const sandbox = await plaidPost('/sandbox/public_token/create', {
    institution_id: process.env.PLAID_SANDBOX_INSTITUTION_ID || 'ins_109508',
    initial_products: ['transactions', 'liabilities'],
    options: {
      webhook: process.env.PLAID_WEBHOOK_URL || undefined
    }
  });

  return exchangePublicToken(sandbox.public_token, sandbox);
}

export async function handlePlaidWebhook(payload) {
  if (payload.webhook_type !== 'LINK' || payload.webhook_code !== 'SESSION_FINISHED') {
    return { handled: false, reason: 'Webhook type ignored.' };
  }

  if (payload.status !== 'SUCCESS') {
    return { handled: true, exchanged: 0, status: payload.status || 'UNKNOWN' };
  }

  const publicTokens = Array.isArray(payload.public_tokens) ? payload.public_tokens : [];
  const exchanges = [];
  for (const publicToken of publicTokens) {
    exchanges.push(await exchangePublicToken(publicToken, payload));
  }

  return {
    handled: true,
    exchanged: exchanges.length,
    itemIds: exchanges.map(exchange => exchange.itemId)
  };
}

export async function exchangePublicToken(publicToken, metadata = {}) {
  assertConfigured();

  const exchange = await plaidPost('/item/public_token/exchange', {
    public_token: publicToken
  });

  const item = await fetchItem(exchange.access_token);
  const institutionId = item.item?.institution_id ?? metadata.institution?.institution_id ?? null;
  const institutionName = await fetchInstitutionName(institutionId);

  upsertPlaidItem({
    itemId: exchange.item_id,
    accessToken: exchange.access_token,
    institutionId,
    institutionName,
    status: 'connected'
  });

  return {
    itemId: exchange.item_id,
    institutionId,
    institutionName,
    requestId: exchange.request_id
  };
}

export async function syncPlaidItems() {
  assertConfigured();

  const items = getPlaidItems();
  const results = [];

  for (const item of items) {
    try {
      const accountsResponse = await plaidPost('/accounts/get', {
        access_token: item.accessToken
      });
      const itemWithInstitution = {
        ...item,
        institutionName: item.institutionName || await fetchInstitutionName(accountsResponse.item?.institution_id)
      };
      upsertPlaidAccounts(itemWithInstitution, accountsResponse.accounts || []);

      const syncResult = await syncTransactions(item);
      const liabilityResult = await syncLiabilities(item);

      updatePlaidItemSyncState(item.itemId, {
        cursor: syncResult.cursor,
        status: 'synced'
      });

      results.push({
        itemId: item.itemId,
        accountCount: accountsResponse.accounts?.length ?? 0,
        addedTransactions: syncResult.added,
        modifiedTransactions: syncResult.modified,
        removedTransactions: syncResult.removed,
        liabilityCount: liabilityResult.count,
        liabilityError: liabilityResult.errorMessage
      });
    } catch (error) {
      updatePlaidItemSyncState(item.itemId, {
        status: 'error',
        errorMessage: error.message
      });
      results.push({
        itemId: item.itemId,
        error: error.message
      });
    }
  }

  return {
    results,
    snapshot: getPlaidSnapshot()
  };
}

async function syncTransactions(item) {
  let cursor = item.transactionsCursor || null;
  let hasMore = true;
  let added = 0;
  let modified = 0;
  let removed = 0;

  while (hasMore) {
    const response = await plaidPost('/transactions/sync', {
      access_token: item.accessToken,
      cursor,
      count: 500
    });

    upsertPlaidTransactions(item.itemId, response.added || []);
    upsertPlaidTransactions(item.itemId, response.modified || []);
    markPlaidTransactionsRemoved(response.removed || []);

    added += response.added?.length ?? 0;
    modified += response.modified?.length ?? 0;
    removed += response.removed?.length ?? 0;
    cursor = response.next_cursor || cursor;
    hasMore = Boolean(response.has_more);
  }

  return { cursor, added, modified, removed };
}

async function syncLiabilities(item) {
  try {
    const response = await plaidPost('/liabilities/get', {
      access_token: item.accessToken
    });
    const liabilities = normalizeLiabilities(response);
    replacePlaidLiabilities(item.itemId, liabilities);
    return { count: liabilities.length, errorMessage: null };
  } catch (error) {
    return { count: 0, errorMessage: error.message };
  }
}

function normalizeLiabilities(response) {
  const credit = response.liabilities?.credit?.map(liability => ({
    type: 'credit',
    account_id: liability.account_id,
    current_balance: liability.last_statement_balance ?? liability.balance_subject_to_apr,
    credit_limit: liability.credit_limit,
    minimum_payment_amount: liability.minimum_payment_amount,
    next_payment_due_date: liability.next_payment_due_date,
    last_statement_balance: liability.last_statement_balance,
    last_statement_issue_date: liability.last_statement_issue_date,
    apr_percentage: liability.aprs?.[0]?.apr_percentage,
    raw: liability
  })) ?? [];

  const student = response.liabilities?.student?.map(liability => ({
    type: 'student',
    account_id: liability.account_id,
    current_balance: liability.outstanding_interest_amount,
    minimum_payment_amount: liability.minimum_payment_amount,
    next_payment_due_date: liability.next_payment_due_date,
    apr_percentage: liability.interest_rate_percentage,
    raw: liability
  })) ?? [];

  const mortgage = response.liabilities?.mortgage?.map(liability => ({
    type: 'mortgage',
    account_id: liability.account_id,
    current_balance: liability.current_late_fee,
    minimum_payment_amount: liability.next_monthly_payment,
    next_payment_due_date: liability.next_payment_due_date,
    raw: liability
  })) ?? [];

  return [...credit, ...student, ...mortgage];
}

async function fetchItem(accessToken) {
  return plaidPost('/item/get', { access_token: accessToken });
}

async function fetchInstitutionName(institutionId) {
  if (!institutionId) {
    return null;
  }

  try {
    const response = await plaidPost('/institutions/get_by_id', {
      institution_id: institutionId,
      country_codes: ['US']
    });
    return response.institution?.name ?? null;
  } catch {
    return null;
  }
}

function extractPublicToken(tokenDetails) {
  if (tokenDetails.public_token) {
    return tokenDetails.public_token;
  }

  const candidates = [
    tokenDetails.link_session,
    ...(Array.isArray(tokenDetails.link_sessions) ? tokenDetails.link_sessions : [])
  ].filter(Boolean);

  for (const candidate of candidates) {
    const publicToken =
      candidate.public_token ||
      candidate.on_success?.public_token ||
      candidate.results?.public_token ||
      candidate.metadata?.public_token ||
      candidate.results?.item_add_results?.find(result => result.public_token)?.public_token ||
      candidate.results?.public_tokens?.[0];
    if (publicToken) {
      return publicToken;
    }
  }

  return null;
}

async function plaidPost(path, body) {
  const response = await fetch(`${plaidBaseURL()}${path}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      client_id: process.env.PLAID_CLIENT_ID,
      secret: process.env.PLAID_SECRET,
      ...withoutUndefined(body)
    })
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = payload.error_message || payload.error_code || `Plaid request failed with HTTP ${response.status}`;
    throw new Error(message);
  }

  return payload;
}

function plaidBaseURL() {
  return process.env.PLAID_BASE_URL || plaidHosts[process.env.PLAID_ENV || 'sandbox'] || plaidHosts.sandbox;
}

function assertConfigured() {
  const status = plaidConfigStatus();
  if (!status.configured) {
    throw new Error('Set PLAID_CLIENT_ID and PLAID_SECRET before using Plaid endpoints.');
  }
}

function withoutUndefined(value) {
  return Object.fromEntries(
    Object.entries(value).filter(([, entry]) => entry !== undefined)
  );
}
