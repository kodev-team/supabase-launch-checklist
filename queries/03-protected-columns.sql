-- Columns that logged-in users may change directly and that usually only the server should set
-- (role, payment, price, credits, status, verification). Each row needs a reason; otherwise revoke it.
select table_name, column_name
from information_schema.column_privileges
where table_schema = 'public' and grantee = 'authenticated' and privilege_type = 'UPDATE'
  and column_name ~* '(^|_)(role|roles|is_admin|admin|paid|is_paid|price|amount|total|balance|credits|plan|tier|status|verified|is_verified|approved)($|_)'
  and table_name in (select tablename from pg_policies where schemaname = 'public' and cmd in ('UPDATE', 'ALL'))
order by 1, 2;
