-- One-time role assignment. Resolves the REAL auth.users UUIDs from the two e-mail addresses you pass in, writes them to
-- public.profiles, and never reads e-mail again. It is NOT callable through the API (execute revoked from every API role) and
-- is never called with literal e-mails from a migration, so no addresses are stored in the repository.
--   select public.bootstrap_roles('<admin e-mail>', '<doda e-mail>');      -- run once in the Supabase SQL editor
create function public.bootstrap_roles(admin_email text, doda_email text) returns table(role text, user_id uuid)
language plpgsql security definer set search_path = '' as $$
declare a uuid; d uuid;
begin
  if lower(btrim(admin_email)) = lower(btrim(doda_email)) then raise exception 'admin and doda must be different accounts'; end if;
  select id into a from auth.users where lower(email) = lower(btrim(admin_email));
  select id into d from auth.users where lower(email) = lower(btrim(doda_email));
  if a is null then raise exception 'no auth user found for the admin e-mail'; end if;
  if d is null then raise exception 'no auth user found for the doda e-mail'; end if;
  insert into public.profiles(id, role) values (a, 'admin') on conflict (id) do nothing;   -- never silently changes an existing role
  insert into public.profiles(id, role) values (d, 'doda')  on conflict (id) do nothing;
  return query select p.role, p.id from public.profiles p where p.id in (a, d) order by p.role;
end $$;
revoke all on function public.bootstrap_roles(text, text) from public, anon, authenticated;
