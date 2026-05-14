# In-Office Attendance Tracker

Track office vs WFH days, annual leave, and NWD on a calendar with England & Wales bank holidays.

**Stack:** static UI on **[Vercel](https://vercel.com)** + managed **Postgres** (e.g. **Neon** or **Vercel Supabase / Postgres** integration) + **`api/`** serverless routes (`pg`, `bcryptjs`, `jsonwebtoken`, JWT sessions). The browser calls same-origin **`/api/*`** only.

## 1. Database

1. Connect a Postgres database to the Vercel project (Neon integration, **Supabase** integration, etc.).
2. **Tables:** the API runs the same DDL as **`neon/schema.sql`** automatically on the first authenticated DB request (`IF NOT EXISTS`). You can still run **`neon/schema.sql`** manually in the provider’s SQL editor if you prefer.

## 2. Vercel

1. Import this GitHub repo into Vercel (or link the existing project).
2. **Build command:** `npm run build` (already set in `vercel.json`). Installs `pg`, `jsonwebtoken`, and `bcryptjs`, and writes optional root **`config.js`** from env (see below).
3. **Environment variables** — the API accepts the usual names **or** the Vercel **Supabase / Postgres** integration names:

   | Name | Notes |
   |------|--------|
   | `DATABASE_URL` **or** `POSTGRES_URL` | Pooled URL (integration often sets `POSTGRES_URL`). |
   | `JWT_SECRET` **or** `SUPABASE_JWT_SECRET` | At least **16 characters** for signing session JWTs. |

4. Deploy, then open `https://your-deployment.vercel.app/api/health` — you should see `{"ok":true}`.

## 3. Local full stack

Static hosting alone (`npx serve .`) does **not** run the API. For auth and cloud saves locally, use the Vercel CLI:

```bash
npm install
vercel link   # once, if not already linked
vercel env pull .env.local   # optional: pulls DATABASE_URL / JWT_SECRET for local dev
npm run build
vercel dev
```

Open the URL Vercel prints (often `http://localhost:3000`). Same-origin `/api/*` works without editing `config.js`.

## 4. Optional `config.js` (`WFH_PUBLIC_API_BASE`)

If the static files and the API run on **different** origins (unusual on Vercel), set **`WFH_PUBLIC_API_BASE`** in `.env.local` or on Vercel, then run **`npm run build`**. The build writes **`config.js`** (gitignored) as:

```js
window.WFH_API = { apiBase: "https://your-api-host" };
```

For a normal deployment, leave it unset so `apiBase` is `""` and the app calls `/api/...` on the same host.

You can also copy **`config.example.js`** to **`config.js`** and set `apiBase` by hand for local experiments.

## 5. Security notes

- **`JWT_SECRET`** / **`SUPABASE_JWT_SECRET`** is server-only; never put it in client code.
- **`DATABASE_URL`** / **`POSTGRES_URL`** is server-only; the browser never sees it.
- Passwords are stored as **bcrypt** hashes in `public.users`. Each user has one **`app_state`** row (`payload` JSONB).

## Git commits in Cursor

If **Commit** fails with **“Bad status code: 401”** / `git-editor.sh`, that is Cursor’s commit editor, not your app. This repo includes **`.vscode/settings.json`** with `git.useEditorAsCommitInput: true` so commits should use the **Source Control message box** instead of that editor. Reload the window after pulling.

If it still fails:

1. **Cursor:** sign out and sign back in (account menu).
2. **Terminal** (in the project folder):  
   `git commit -m "Describe your change"`  
3. Or set a simple editor once for this repo:  
   `git config core.editor nano`

## Migrating from Supabase or older stacks

There is **no automatic migration** of rows from Supabase `auth.users` / `app_state`. Run **`neon/schema.sql`**, deploy with env vars set, then **register a new account** (or export/import JSON manually if you kept backups).
