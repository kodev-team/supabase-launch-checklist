-- Policies that allow every row. Writes (INSERT, UPDATE, DELETE, ALL) should be none;
-- reads (SELECT) only on tables that are meant to be public.
select tablename, policyname, cmd, roles
from pg_policies
where schemaname = 'public'
  and (coalesce(trim(qual), 'true') in ('true', '(true)') and cmd <> 'INSERT'
       or coalesce(trim(with_check), 'true') in ('true', '(true)') and cmd = 'INSERT')
order by cmd <> 'SELECT' desc, tablename, policyname;
