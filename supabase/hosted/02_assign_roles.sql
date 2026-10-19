-- Run once AFTER 01_apply_all.sql. Replace the two placeholders with the real addresses in the SQL editor ONLY (do not commit them).
-- Resolves the real auth.users UUIDs; never changes an existing role; refuses identical addresses.
select * from public.bootstrap_roles('<ADMIN EMAIL>', '<DODA EMAIL>');
