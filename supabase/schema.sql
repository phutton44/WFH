-- Run in Supabase: Dashboard → SQL → New query.
-- PostgreSQL + Row Level Security; `user_id` ties to Supabase Auth.

create table if not exists public.app_state (
  user_id uuid primary key references auth.users (id) on delete cascade,
  payload jsonb not null,
  updated_at timestamptz not null default now()
);

create index if not exists app_state_updated_at_idx on public.app_state (updated_at desc);

alter table public.app_state enable row level security;

create policy "app_state_select_own"
  on public.app_state for select
  using (auth.uid() = user_id);

create policy "app_state_insert_own"
  on public.app_state for insert
  with check (auth.uid() = user_id);

create policy "app_state_update_own"
  on public.app_state for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "app_state_delete_own"
  on public.app_state for delete
  using (auth.uid() = user_id);
