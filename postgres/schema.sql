-- Railway PostgreSQL (or any Postgres 14+). Run once: Railway dashboard → Postgres → Query, or psql.
-- Requires gen_random_uuid(): enable pgcrypto (standard on Railway).

create extension if not exists "pgcrypto";

create table if not exists public.users (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  password_hash text not null,
  created_at timestamptz not null default now()
);

create index if not exists users_email_lower_idx on public.users (lower(email));

create table if not exists public.app_state (
  user_id uuid primary key references public.users (id) on delete cascade,
  payload jsonb not null,
  updated_at timestamptz not null default now()
);

create index if not exists app_state_updated_at_idx on public.app_state (updated_at desc);
