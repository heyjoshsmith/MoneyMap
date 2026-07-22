import http from 'node:http';
import { URL } from 'node:url';
import { getImports, getPlaidAccounts, getPlaidConnections, getPlaidLiabilities, getPlaidSnapshot, getPlaidTransactions, getSummary, getTransactions } from './db.js';
import { processExistingFiles, watchInbox } from './importer.js';
import { completeHostedLink, createHostedLinkToken, createSandboxConnection, exchangePublicToken, handlePlaidWebhook, plaidConfigStatus, syncPlaidItems } from './plaid.js';

const host = process.env.HOST || '127.0.0.1';
const port = Number(process.env.PORT || 3030);

processExistingFiles();
watchInbox();

const server = http.createServer(async (request, response) => {
  const url = new URL(request.url, `http://${request.headers.host || `${host}:${port}`}`);

  try {
    if (request.method === 'GET' && url.pathname === '/health') {
      return sendJson(response, 200, {
        ok: true,
        host,
        port,
        plaid: plaidConfigStatus(),
        timestamp: new Date().toISOString()
      });
    }

    if (request.method === 'GET' && url.pathname === '/api/summary') {
      return sendJson(response, 200, getSummary());
    }

    if (request.method === 'GET' && url.pathname === '/api/imports') {
      return sendJson(response, 200, getImports());
    }

    if (request.method === 'GET' && url.pathname === '/api/transactions') {
      const requestedLimit = Number(url.searchParams.get('limit') || 50);
      const limit = normalizedLimit(requestedLimit, 500, 50);
      return sendJson(response, 200, getTransactions(limit));
    }

    if (request.method === 'POST' && url.pathname === '/api/plaid/link-token') {
      return sendJson(response, 200, await createHostedLinkToken());
    }

    if (request.method === 'POST' && url.pathname === '/api/plaid/complete-hosted-link') {
      const body = await readJson(request);
      if (!body.linkToken) {
        return sendJson(response, 400, { error: 'linkToken is required.' });
      }
      return sendJson(response, 200, await completeHostedLink(body.linkToken));
    }

    if (request.method === 'POST' && url.pathname === '/api/plaid/exchange-public-token') {
      const body = await readJson(request);
      if (!body.publicToken) {
        return sendJson(response, 400, { error: 'publicToken is required.' });
      }
      return sendJson(response, 200, await exchangePublicToken(body.publicToken));
    }

    if (request.method === 'POST' && url.pathname === '/api/plaid/webhook') {
      return sendJson(response, 200, await handlePlaidWebhook(await readJson(request)));
    }

    if (request.method === 'POST' && url.pathname === '/api/plaid/sandbox-public-token') {
      return sendJson(response, 200, await createSandboxConnection());
    }

    if (request.method === 'POST' && url.pathname === '/api/plaid/sync') {
      return sendJson(response, 200, await syncPlaidItems());
    }

    if (request.method === 'GET' && url.pathname === '/api/plaid/snapshot') {
      const requestedLimit = Number(url.searchParams.get('limit') || 200);
      const limit = normalizedLimit(requestedLimit, 1000, 200);
      return sendJson(response, 200, getPlaidSnapshot(limit));
    }

    if (request.method === 'GET' && url.pathname === '/api/plaid/connections') {
      return sendJson(response, 200, getPlaidConnections());
    }

    if (request.method === 'GET' && url.pathname === '/api/plaid/accounts') {
      return sendJson(response, 200, getPlaidAccounts());
    }

    if (request.method === 'GET' && url.pathname === '/api/plaid/transactions') {
      const requestedLimit = Number(url.searchParams.get('limit') || 200);
      const limit = normalizedLimit(requestedLimit, 1000, 200);
      return sendJson(response, 200, getPlaidTransactions(limit));
    }

    if (request.method === 'GET' && url.pathname === '/api/plaid/liabilities') {
      return sendJson(response, 200, getPlaidLiabilities());
    }

    return sendJson(response, 404, { error: 'Not found' });
  } catch (error) {
    const statusCode = error.message?.includes('PLAID_CLIENT_ID') ? 503 : 500;
    return sendJson(response, statusCode, {
      error: error.message || 'Unexpected server error'
    });
  }
});

server.listen(port, host, () => {
  console.log(`MoneyMap prototype server listening on http://${host}:${port}`);
});

function sendJson(response, statusCode, body) {
  response.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8'
  });
  response.end(JSON.stringify(body, null, 2));
}

function normalizedLimit(value, maximum, fallback) {
  return Number.isFinite(value) ? Math.min(Math.max(value, 1), maximum) : fallback;
}

function readJson(request) {
  return new Promise((resolve, reject) => {
    let body = '';
    request.on('data', chunk => {
      body += chunk;
      if (body.length > 1_000_000) {
        request.destroy();
        reject(new Error('Request body is too large.'));
      }
    });
    request.on('end', () => {
      if (!body) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(body));
      } catch {
        reject(new Error('Request body must be valid JSON.'));
      }
    });
    request.on('error', reject);
  });
}
