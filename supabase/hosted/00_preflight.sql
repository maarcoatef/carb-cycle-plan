-- READ-ONLY. Run first in the SQL editor of project oxqcprgreelxfjhlqpxl (check the project ref in the URL!).
-- The migrations revoke default privileges and force RLS on EVERY table in schema public, so the project's public schema must be empty
-- (or contain only tables you are happy to lock down). Expected result: 0 rows.
select tablename from pg_tables where schemaname = 'public' order by 1;
-- Expected: no existing public.profiles / foods / etc. and exactly the two auth users:
select count(*) as auth_users from auth.users;
select id, email, email_confirmed_at is not null as confirmed from auth.users order by created_at;
