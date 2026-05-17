-- Run once in Neon: SQL Editor (Neon dashboard) or psql against your branch.
-- Creates app users + one JSON row per user for attendance state.

create extension if not exists "pgcrypto";

create table if not exists public.users (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  password_hash text,
  google_sub text unique,
  apple_sub text unique,
  auth_provider text not null default 'password',
  created_at timestamptz not null default now()
);

alter table public.users alter column password_hash drop not null;
alter table public.users add column if not exists google_sub text;
alter table public.users add column if not exists apple_sub text;
alter table public.users add column if not exists auth_provider text not null default 'password';

create index if not exists users_email_lower_idx on public.users (lower(email));
create unique index if not exists users_google_sub_idx on public.users (google_sub) where google_sub is not null;
create unique index if not exists users_apple_sub_idx on public.users (apple_sub) where apple_sub is not null;

create table if not exists public.app_state (
  user_id uuid primary key references public.users (id) on delete cascade,
  payload jsonb not null,
  updated_at timestamptz not null default now()
);

create index if not exists app_state_updated_at_idx on public.app_state (updated_at desc);

create table if not exists public.password_reset_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users (id) on delete cascade,
  token_hash text not null,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists password_reset_tokens_hash_idx on public.password_reset_tokens (token_hash);
create index if not exists password_reset_tokens_user_idx on public.password_reset_tokens (user_id);
