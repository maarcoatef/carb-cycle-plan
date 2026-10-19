-- LOCAL TEST SUPPORT ONLY (never applied to hosted Supabase, which has the real storage service).
-- Gives a local stack that runs WITHOUT the storage container the minimal storage.* objects the photo policies reference.
-- Run once as supabase_admin:
--   docker exec -i supabase_db_carb-cycle-plan psql -U supabase_admin -d postgres < supabase/support/local_storage_stub.sql
create schema if not exists storage;
create table if not exists storage.buckets (id text primary key, name text, public boolean default false, file_size_limit bigint, allowed_mime_types text[]);
create table if not exists storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id), name text, owner uuid, metadata jsonb);
alter table storage.objects enable row level security;
create or replace function storage.foldername(name text) returns text[] language sql immutable as
  'select (string_to_array(name, ''/''))[1:array_length(string_to_array(name, ''/''),1)-1]';
grant usage on schema storage to anon, authenticated, postgres;
grant all on storage.objects to anon, authenticated, postgres;
grant all on storage.buckets to postgres;
grant select on storage.buckets to anon, authenticated;
