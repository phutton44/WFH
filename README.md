# In-Office Attendance Tracker

Track office vs WFH days, annual leave, and NWD on a calendar with England & Wales bank holidays. Data syncs to [Supabase](https://supabase.com) (PostgreSQL + email/password auth).

## Run locally

1. Copy `config.example.js` to `config.js` and add your **Project URL** and **anon** key from Supabase → Project Settings → API.
2. In Supabase **SQL Editor**, run `supabase/schema.sql`.
3. Open `index.html` with a local server (or double-click if your browser allows), e.g. `npx serve .`

## GitHub Pages

After enabling Pages (Settings → Pages → deploy from branch `main` / root), set **Site URL** and redirect URLs in Supabase → Authentication → URL configuration to your `https://<user>.github.io/<repo>/` URL.
