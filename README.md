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
   | **`GOOGLE_CLIENT_ID`** | Optional. Google OAuth **Web application** client ID for “Continue with Google”. Also accepted as **`WFH_GOOGLE_CLIENT_ID`**. Add your production and local origins in Google Cloud. |
   | **`RESEND_API_KEY`** | Optional but required to **send** reset mail. [Resend](https://resend.com) API key. |
   | **`RESEND_FROM_EMAIL`** | Optional but required to **send** reset mail. Verified sender in Resend (e.g. `App <noreply@yourdomain.com>`). Alias: **`RESEND_FROM`**. |
   | **`WFH_PUBLIC_ORIGIN`** | Optional. Full public site URL without a trailing slash (e.g. `https://your-app.vercel.app`). Used to build reset links when the request’s Host / forwarded headers are missing or wrong. |

   **Compatibility:** some older Vercel project templates expose **`POSTGRES_URL`** instead of `DATABASE_URL`, or **`SUPABASE_JWT_SECRET`** instead of `JWT_SECRET`. The server reads those as fallbacks so you do not have to rename env vars when moving projects—**your database is still Neon Postgres**, not the old Supabase browser client.

4. Deploy, then open `https://your-deployment.vercel.app/api/health` — you should see `{"ok":true}`.

### Password reset email (Resend)

Forgot-password uses **[Resend](https://resend.com)** only (no SMTP or other mail providers in this repo). To actually deliver mail:

1. Create a Resend account, verify a **sending domain** (or use Resend’s onboarding sender for tests).
2. In Vercel → Environment variables, set **`RESEND_API_KEY`** and **`RESEND_FROM_EMAIL`** (must match a verified sender / domain in Resend).
3. Set **`WFH_PUBLIC_ORIGIN`** to your live site URL (no trailing slash), e.g. `https://your-app.vercel.app`, so the reset link in the email points at **`/reset.html?token=…`** on the correct host.

If those variables are missing, **`POST /api/auth/forgot-password`** still returns **200** with a generic message (no account enumeration), but no email is sent.

### Google sign-in

Google sign-in is optional. To enable it:

1. In Google Cloud Console → APIs & Services → Credentials, create an **OAuth client ID** with application type **Web application**.
2. Add your app origins under **Authorized JavaScript origins**, for example `https://your-app.vercel.app` and local `http://localhost:3000`.
3. In Vercel → Environment Variables, set **`GOOGLE_CLIENT_ID`** to that client ID, then redeploy. The build writes the public client ID to `config.js`; the API also uses the same value to verify Google ID tokens server-side.

Users who choose **Continue with Google** are created using Google’s verified email address and receive the same app JWT session as email/password users. Existing password users can also use Google if the Google account has the same verified email address.

### Cleaning up after Supabase on the same Vercel project

If you previously wired **Supabase** and then moved to **Neon** (or the Cursor marketplace Neon flow), tidy the **Vercel project**, not this repo:

1. **Settings → Environment variables:** delete unused **`NEXT_PUBLIC_SUPABASE_URL`**, **`NEXT_PUBLIC_SUPABASE_ANON_KEY`**, and any **`SUPABASE_SERVICE_ROLE_KEY`** (or similar). This app’s static files do not read them; leaving them around is confusing and widens the blast radius if envs leak.
2. **Settings → Integrations:** disconnect the **Supabase** integration if it is still attached, so it does not keep syncing or re-injecting variables.
3. **JWT:** set **`JWT_SECRET`** (≥16 characters) for this app. You may then remove **`SUPABASE_JWT_SECRET`** unless something else still expects that exact name — the API only uses `SUPABASE_JWT_SECRET` as a **fallback** when `JWT_SECRET` is unset (`api/_shared.js`).
4. **Database URL:** ensure **`DATABASE_URL`** or **`POSTGRES_URL`** is the **Neon** pooled string from the Neon integration (or pasted manually), not an old Supabase Postgres URL.

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

## 5. macOS desktop app (Electron)

The macOS app reuses the same static frontend files and points them at the hosted Vercel API by default.

```bash
npm install
npm run electron:dev    # run the desktop app locally
npm run mac:dir         # build dist/mac-arm64/WFH Attendance.app
npm run mac:package     # build DMG + ZIP installers
```

By default, desktop builds set **`WFH_PUBLIC_API_BASE=https://wfh-one.vercel.app`** before writing `config.js`. Override that if you want the desktop app to use another API:

```bash
WFH_PUBLIC_API_BASE=https://your-app.vercel.app npm run mac:package
```

## 6. iOS app (Swift)

The iOS project lives at **`ios/WFHAttendanceIOS.xcodeproj`**. It is a native dark-mode SwiftUI app that talks to the same Vercel/Neon backend as the web app. It supports email sign-in/register, synced attendance state, separate Calendar / KPIs / Settings tabs, KPI dashboards, a native month planner with multi-select, day-type actions, and settings.

To test it:

1. Open **`ios/WFHAttendanceIOS.xcodeproj`** in Xcode.
2. Select the **`WFHAttendanceIOS`** scheme.
3. Pick an iPhone simulator.
4. Press **Run**.

Current bundle id: **`com.paulhutton.wfhattendance.ios`**.

## 7. Security notes

- **`JWT_SECRET`** (or the legacy fallback name **`SUPABASE_JWT_SECRET`** on some Vercel templates) is server-only; never put it in client code.
- **`DATABASE_URL`** / **`POSTGRES_URL`** is server-only; the browser never sees it.
- Passwords are stored as **bcrypt** hashes in `public.users`. Each user has one **`app_state`** row (`payload` JSONB).
- Google users do not need a local password; Google ID tokens are verified server-side against Google’s public signing keys and your configured `GOOGLE_CLIENT_ID`.
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
