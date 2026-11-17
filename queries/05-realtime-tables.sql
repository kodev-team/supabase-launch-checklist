-- Tables sent over Realtime (Postgres Changes) and whether RLS is on. Every row should say true,
-- and tables with private data should have policies.
select pt.schemaname, pt.tablename, c.relrowsecurity as rls_on
from pg_publication_tables pt
join pg_namespace n on n.nspname = pt.schemaname
join pg_class c on c.relnamespace = n.oid and c.relname = pt.tablename
where pt.pubname = 'supabase_realtime'
order by 1, 2;
