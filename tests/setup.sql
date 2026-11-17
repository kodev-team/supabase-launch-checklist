-- Minimal Supabase-like database with one planted problem per query. Test data only.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$ select null::uuid $$;
create schema storage;
create table storage.buckets (id text primary key, public boolean default false);
create table storage.objects (id uuid primary key, bucket_id text, name text, owner uuid);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$ select string_to_array(name, '/') $$;
grant usage on schema public to anon, authenticated;
alter default privileges in schema public grant all on tables to anon, authenticated;

create table public.notes (id int primary key, user_id uuid, body text);            -- 01: RLS off
create table public.orders (id int primary key, user_id uuid, total int, status text);
alter table public.orders enable row level security;
create policy "own orders" on public.orders for select to authenticated using ((select auth.uid()) = user_id);
create policy "edit own orders" on public.orders for update to authenticated using ((select auth.uid()) = user_id); -- 03: total, status
create table public.posts (id int primary key, body text);
alter table public.posts enable row level security;
create policy "anyone reads" on public.posts for select using (true);                 -- 02: read, fine if public
create policy "anyone writes" on public.posts for insert to anon with check (true);    -- 02: write, problem
create table public.clean (id int primary key, user_id uuid);
alter table public.clean enable row level security;
create policy "own rows" on public.clean for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
insert into storage.buckets values ('avatars', true), ('invoices', false);
create policy "own folder" on storage.objects for select to authenticated
  using (bucket_id = 'invoices' and (storage.foldername(name))[1] = (select auth.uid())::text);
create publication supabase_realtime for table public.orders, public.notes;
