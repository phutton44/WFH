# In-Office Attendance Tracker

Track office vs WFH days, annual leave, and NWD on a calendar with England & Wales bank holidays.

**Stack:** static UI in this repo on **[Vercel](https://vercel.com)** + **[Neon](https://neon.tech)** Postgres + **serverless API** under `api/` (JWT auth, `bcryptjs`, `pg`). The browser uses `fetch` to same-origin `/api/*`; there is **no** Supabase.

## 1. Neon

1. Create a Neon project (or use the Vercel **Neon** integration so `DATABASE_URL` is set on the project).
2. In the Neon **SQL Editor** (or any `psql` session), run **`neon/schema.sql`** once. That creates `public.users` and `public.app_state`.

## 2. Vercel

1. Import this GitHub repo into Vercel (or link the existing project).
2. **Build command:** `npm run build` (already set in `vercel.json`). Installs `pg`, `jsonwebtoken`, and `bcryptjs`, and writes optional root **`config.js`** from env (see below).
3. **Environment variables** (Project → Settings → Environment Variables), for **Production** (and Preview if you use it):

   | Name | Notes |
   |------|--------|
   | `DATABASE_URL` | Pooled connection string from Neon (often filled by the Neon integration). |
   | `JWT_SECRET` | Any long random string (**at least 16 characters**). Used to sign session JWTs. |

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

- **`JWT_SECRET`** is server-only; never put it in client code.
- **`DATABASE_URL`** is server-only; the browser never sees it.
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
