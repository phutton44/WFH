# In-Office Attendance Tracker

Track office vs WFH days, annual leave, and NWD on a calendar with England & Wales bank holidays.

**Stack:** static UI on **[Vercel](https://vercel.com)** + **[Neon](https://neon.tech)** Postgres (via the Vercel **Neon** integration or hand-set **`DATABASE_URL`**) + **`api/`** serverless routes (`pg`, `bcryptjs`, `jsonwebtoken`, JWT sessions). The browser only calls same-origin **`/api/*`** (no database client SDK in the page).

## 1. Database (Neon)

1. Add **[Neon](https://neon.tech)** to your Vercel project and connect it, or paste a Neon **pooled** connection string into **`DATABASE_URL`** under Vercel → Environment variables.
2. **Tables:** the API applies the same DDL as **`neon/schema.sql`** automatically on the first authenticated request (`IF NOT EXISTS`). You can still run **`neon/schema.sql`** once in the Neon SQL editor if you prefer.

## 2. Vercel

1. Import this GitHub repo into Vercel (or link the existing project).
2. **Build command:** `npm run build` (already set in `vercel.json`). Installs `pg`, `jsonwebtoken`, and `bcryptjs`, and writes optional root **`config.js`** from env (see below).
3. **Environment variables** (Neon-first; set these in Vercel → Production):

   | Name | Notes |
   |------|--------|
   | **`DATABASE_URL`** | Neon pooled connection string (often provided by the Neon integration). |
   | **`JWT_SECRET`** | Any random string, **≥16 characters**, used only by **`api/`** to sign session JWTs. |

   **Compatibility:** some older Vercel project templates expose **`POSTGRES_URL`** instead of `DATABASE_URL`, or **`SUPABASE_JWT_SECRET`** instead of `JWT_SECRET`. The server reads those as fallbacks so you do not have to rename env vars when moving projects—**your database is still Neon Postgres**, not the old Supabase browser client.

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

- **`JWT_SECRET`** (or the legacy fallback name **`SUPABASE_JWT_SECRET`** on some Vercel templates) is server-only; never put it in client code.
- **`DATABASE_URL`** / **`POSTGRES_URL`** is server-only; the browser never sees it.
- Passwords are stored as **bcrypt** hashes in `public.users`. Each user has one **`app_state`** row (`payload` JSONB).
- **Never commit** `.env`, `.env.local`, or any file that contains real keys. This repo **`.gitignores`** them; use **`.env.example`** as a template only. If secrets were ever committed or pasted into a ticket/chat, **rotate them** in Neon / Vercel and consider **`git filter-repo`** (or BFG) to purge history on a private fork before wider sharing.

## Git commits in Cursor

If **Commit** fails with **“Bad status code: 401”** / `git-editor.sh`, that is Cursor’s commit editor, not your app. This repo includes **`.vscode/settings.json`** with `git.useEditorAsCommitInput: true` so commits should use the **Source Control message box** instead of that editor. Reload the window after pulling.

If it still fails:

1. **Cursor:** sign out and sign back in (account menu).
2. **Terminal** (in the project folder):  
   `git commit -m "Describe your change"`  
3. Or set a simple editor once for this repo:  
   `git config core.editor nano`

## Migrating from older hosted stacks

If you previously used **Supabase Auth + client** or another host, there is **no automatic migration** of old `auth.users` / `app_state` rows. Point Vercel at **Neon**, deploy with env vars set, then **register a new account** (or export/import JSON manually if you kept backups).
