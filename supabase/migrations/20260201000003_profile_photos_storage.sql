-- Private bucket + owner-only policies for profile photos. Path convention: <auth.uid()>/avatar.jpg — only Doda, never admin.
-- Wrapped in a function so the same SQL works on hosted Supabase (storage schema already present during `db push`)
-- and locally (storage schema is created by the storage service after migrations; supabase/seed.sql calls it then).
create function public.setup_profile_photo_storage() returns void language plpgsql set search_path = '' as $fn$
begin
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('profile-photos', 'profile-photos', false, 2097152, array['image/jpeg','image/png'])
  on conflict (id) do update set public = false, file_size_limit = 2097152, allowed_mime_types = array['image/jpeg','image/png'];

  execute 'drop policy if exists profile_photos_select_own on storage.objects';
  execute 'drop policy if exists profile_photos_insert_own on storage.objects';
  execute 'drop policy if exists profile_photos_update_own on storage.objects';
  execute 'drop policy if exists profile_photos_delete_own on storage.objects';
  execute $p$create policy profile_photos_select_own on storage.objects for select to authenticated
    using (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text and public.is_doda())$p$;
  execute $p$create policy profile_photos_insert_own on storage.objects for insert to authenticated
    with check (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text and public.is_doda())$p$;
  execute $p$create policy profile_photos_update_own on storage.objects for update to authenticated
    using (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text and public.is_doda())
    with check (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text and public.is_doda())$p$;
  execute $p$create policy profile_photos_delete_own on storage.objects for delete to authenticated
    using (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text and public.is_doda())$p$;
end $fn$;
revoke all on function public.setup_profile_photo_storage() from public, anon, authenticated;

do $$ begin
  if to_regclass('storage.objects') is not null and to_regclass('storage.buckets') is not null then
    perform public.setup_profile_photo_storage();
  end if;
end $$;
