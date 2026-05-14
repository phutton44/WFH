-- Irreversible: removes all accounts and saved calendar JSON.
-- Run in Neon → SQL Editor on this project’s database.
-- Everyone must register again afterward.

TRUNCATE TABLE public.users RESTART IDENTITY CASCADE;
