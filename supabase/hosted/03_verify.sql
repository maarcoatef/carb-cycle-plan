-- READ-ONLY verification, run after 01 and 02. Every check should return the expected value in the comment.
select tablename, rowsecurity from pg_tables where schemaname='public' order by 1;                         -- all rowsecurity = true
select count(*) as tables_without_rls from pg_tables where schemaname='public' and not rowsecurity;       -- 0
select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='r' and not c.relforcerowsecurity;                              -- 0 rows
select p.role, u.email from public.profiles p join auth.users u on u.id=p.id order by 1;                  -- one admin, one doda
select id, public, file_size_limit, allowed_mime_types from storage.buckets where id='profile-photos';   -- public = false, 2097152
select policyname, cmd, roles from pg_policies where schemaname in ('public','storage') order by 1, 2;   -- no policy for role anon; none mentions email
select count(*) as anon_table_grants from information_schema.role_table_grants where table_schema='public' and grantee='anon'; -- 0
select count(*) as unconditional_policies from pg_policies where schemaname='public' and (qual='true' or with_check='true'); -- 0
