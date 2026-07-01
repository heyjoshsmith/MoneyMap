# MoneyMap Local Server Prototype

This is a small local-only prototype for the kind of Mac mini helper server that adds value to MoneyMap without replacing SwiftData or iCloud.

## What It Does

- Watches an `inbox/` folder for CSV files.
- Imports transaction rows into a local SQLite database.
- Moves processed files into `processed/`.
- Exposes a local API on your LAN.

## Why This Fits MoneyMap

MoneyMap already has:

- local SwiftData storage
- CloudKit/iCloud sync
- manual CSV import in the app
- planning and recommendation logic in-app

This prototype focuses on the gap a Mac mini can fill well:

- background file watching
- unattended imports
- lightweight reporting
- a stable local API for your apps, dashboards, or Shortcuts

## Run It

```bash
cd server-prototype
node src/server.js
```

The server listens on `http://127.0.0.1:3030` by default.

To allow access from your other devices on the same network:

```bash
HOST=0.0.0.0 node src/server.js
```

Then use your Mac mini's local IP address, for example:

`http://192.168.1.50:3030/api/summary`

## Drop Files Here

Put CSV files into:

`server-prototype/inbox/`

Expected columns:

- `Transaction Date`
- `Clearing Date`
- `Description`
- `Merchant`
- `Category`
- `Type`
- `Amount (USD)`
- `Purchased By`

This matches the current MoneyMap transaction import shape closely.

## API Endpoints

- `GET /health`
- `GET /api/summary`
- `GET /api/imports`
- `GET /api/transactions?limit=50`

## Notes

- Data stays local to this Mac.
- No authentication is included because this is meant for local development on a trusted network.
- If you want the server reachable from other devices, prefer LAN only and keep it behind your router.
- If you later install `npm`, you can swap the HTTP layer to Express without changing the watcher/import architecture.
