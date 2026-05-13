# In-Office Attendance Tracker

Track office vs WFH days, annual leave, and NWD on a calendar with England & Wales bank holidays.

**Database:** [PostgreSQL](https://www.postgresql.org/) on [Railway](https://railway.app). The browser app talks to a small **Node API** in `server/` (JWT auth + JSON in `public.app_state`). Railway hosts both Postgres and the API.

## One-time setup (Railway)

1. **Postgres:** Create a Railway **PostgreSQL** resource. Open **Query** (or any SQL client), paste `postgres/schema.sql`, and run it.
2. **API service:** Create an **empty** service from this GitHub repo. Set **Root Directory** to `server`. Under **Variables**, add:
   - `DATABASE_URL` — use **Reference** to the Postgres plugin’s `DATABASE_URL`.
   - `JWT_SECRET` — a long random string (16+ characters).
   - `CORS_ORIGIN` — the exact browser origin(s) allowed to call the API, comma-separated (no trailing slashes), e.g. `https://yourname.github.io,http://localhost:8080` for GitHub Pages + local testing.
3. Deploy and copy the service **public URL** (HTTPS).

## Frontend config

1. Copy `config.example.js` to `config.js`.
2. Set `window.WFH_API.baseUrl` to your API URL (no trailing slash), e.g. `https://wfh-api-production-xxxx.up.railway.app`.
3. Serve the static files (GitHub Pages, `npx serve .`, etc.) and reload the app. Register once; data syncs to Postgres after each change (debounced) and on sign-out.

## Local development

- **API:** `cd server && cp .env.example .env` — fill `DATABASE_URL`, `JWT_SECRET`, and `CORS_ORIGIN` (e.g. `http://127.0.0.1:3001` if the static site runs on port 3001). Run `npm install` and `npm start` (default port `3000`).
- **Static app:** Point `config.js` at `http://localhost:3000` if the API is local; ensure that origin is listed in `CORS_ORIGIN` on the server.

## GitHub Pages

Enable Pages from `main` (root). Set `CORS_ORIGIN` on Railway to `https://<user>.github.io` (origin has no repo path). Put the same Railway API URL in `config.js` in the repo (or use a private fork pattern if you prefer not to commit `config.js`—then use a build step or Pages secrets; simplest is committing `config.js` with only the public API URL).

## Migrating from Supabase

Older setups used Supabase. This repo now targets **Railway Postgres + the included API** only. Supabase accounts and rows are **not** moved automatically; register again on the new stack or export/import manually if you need old data.
