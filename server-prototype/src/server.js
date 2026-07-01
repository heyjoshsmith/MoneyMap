import http from 'node:http';
import { URL } from 'node:url';
import { getImports, getSummary, getTransactions } from './db.js';
import { processExistingFiles, watchInbox } from './importer.js';

const host = process.env.HOST || '127.0.0.1';
const port = Number(process.env.PORT || 3030);

processExistingFiles();
watchInbox();

const server = http.createServer((request, response) => {
  const url = new URL(request.url, `http://${request.headers.host || `${host}:${port}`}`);

  if (request.method !== 'GET') {
    return sendJson(response, 405, { error: 'Method not allowed' });
  }

  if (url.pathname === '/health') {
    return sendJson(response, 200, {
      ok: true,
      host,
      port,
      timestamp: new Date().toISOString()
    });
  }

  if (url.pathname === '/api/summary') {
    return sendJson(response, 200, getSummary());
  }

  if (url.pathname === '/api/imports') {
    return sendJson(response, 200, getImports());
  }

  if (url.pathname === '/api/transactions') {
    const requestedLimit = Number(url.searchParams.get('limit') || 50);
    const limit = Number.isFinite(requestedLimit) ? Math.min(Math.max(requestedLimit, 1), 500) : 50;
    return sendJson(response, 200, getTransactions(limit));
  }

  return sendJson(response, 404, { error: 'Not found' });
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
