# In-Office Attendance Tracker

Track office vs WFH days, annual leave, and NWD on a calendar with England & Wales bank holidays.

**Stack:** static site (this repo) on **[Vercel](https://vercel.com)** + **[Supabase](https://supabase.com)** (managed **PostgreSQL**, Auth, Row Level Security). The browser uses the Supabase JS client; there is **no** custom Node API in this repo.

## 1. Supabase

1. Create a project (free tier is fine).
2. **Project Settings → API** — copy **Project URL** and **anon public** key into `config.js` (from `config.example.js`).
3. **SQL Editor** — paste and run `supabase/schema.sql` (creates `app_state` + RLS).
4. **Authentication → URL configuration** — add:
   - your **Vercel production URL** (e.g. `https://your-app.vercel.app`),
   - and `http://localhost:PORT` for local testing.
5. Optional while testing: **Authentication → Providers → Email** — turn off **Confirm email** so sign-up can sign in immediately.

## 2. Vercel

1. Import this GitHub repo into Vercel.
2. **Framework preset:** Other (static), or leave default — no build command required; `index.html` is at the repo root.
3. Ensure `config.js` exists for deploys:
   - Easiest: create `config.js` locally (gitignored) and use **Vercel → Settings → Environment Variables** only if you add a small build step later; **or** commit `config.js` with **only** the public anon key (Supabase anon key is designed to be public in the client; still use **RLS** so data stays per-user).

## 3. Local preview

```bash
npx serve .
```

Open the printed `http://localhost:…` URL, add that origin under Supabase Auth URLs, and use the same `config.js` values.

## Git commits in Cursor

If **Commit** fails with **“Bad status code: 401”** / `git-editor.sh`, that is Cursor’s commit editor, not your app. This repo includes **`.vscode/settings.json`** with `git.useEditorAsCommitInput: true` so commits should use the **Source Control message box** instead of that editor. Reload the window after pulling.

If it still fails:

1. **Cursor:** sign out and sign back in (account menu).
2. **Terminal** (in the project folder):  
   `git commit -m "Describe your change"`  
3. Or set a simple editor once for this repo:  
   `git config core.editor nano`

## Migrating from Railway

If you previously used the Railway + `server/` API, that data is **not** moved automatically. Create a Supabase project, run the SQL above, and **register again** (or export/import manually).
