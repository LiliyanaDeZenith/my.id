-- =====================================================================
-- Klipin: skema Supabase
-- Tempel seluruh isi file ini di Supabase > SQL Editor, lalu klik Run.
-- Aman dijalankan berulang kali.
-- =====================================================================

-- 1. Tabel ------------------------------------------------------------

create table if not exists public.posts (
  id text primary key check (id ~ '^[a-z0-9]{6,40}$'),
  a  text not null check (a ~ '^[0-9a-f-]{36}/[0-9a-f]{32}$'),  -- path file di bucket media
  k  text not null check (k in ('v', 'i')),                      -- v = video, i = foto
  ti text not null default '' check (char_length(ti) <= 80),     -- judul
  ds text not null default '' check (char_length(ds) <= 300),    -- keterangan
  o  uuid not null default auth.uid() references auth.users (id) on delete cascade,
  t  bigint not null,                                            -- waktu unggah (ms)
  u  boolean not null default false,                             -- true = hanya lewat link
  z  bigint not null default 0 check (z >= 0)                    -- ukuran byte
);
create index if not exists posts_t_idx on public.posts (t desc);
create index if not exists posts_o_idx on public.posts (o);

create table if not exists public.profiles (
  id   uuid primary key references auth.users (id) on delete cascade,
  name text not null default '' check (char_length(name) <= 40),
  bio  text not null default '' check (char_length(bio) <= 160)
);

create table if not exists public.user_settings (
  id       uuid primary key references auth.users (id) on delete cascade,
  saved    jsonb not null default '[]'::jsonb,
  theme    text not null default 'auto' check (theme in ('auto', 'light', 'dark')),
  autoplay boolean not null default true,
  vis      text not null default 'public' check (vis in ('public', 'link'))
);

-- Admin boleh menghapus unggahan siapa pun. Isi lewat SQL Editor (lihat README).
create table if not exists public.admins (
  id uuid primary key references auth.users (id) on delete cascade
);

-- 2. Fungsi -----------------------------------------------------------

create or replace function public.is_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$ select exists (select 1 from public.admins where id = auth.uid()) $$;

-- Membuka satu unggahan lewat link, termasuk yang berstatus "hanya lewat link".
create or replace function public.get_post(p_id text)
returns setof public.posts
language sql stable security definer
set search_path = public
as $$ select * from public.posts where id = p_id $$;

grant execute on function public.is_admin() to anon, authenticated;
grant execute on function public.get_post(text) to anon, authenticated;

-- 3. Hak akses dan RLS ------------------------------------------------

grant usage on schema public to anon, authenticated;
grant select on public.posts, public.profiles to anon;
grant select, insert, update, delete on public.posts, public.profiles, public.user_settings to authenticated;
grant select on public.admins to authenticated;

alter table public.posts         enable row level security;
alter table public.profiles      enable row level security;
alter table public.user_settings enable row level security;
alter table public.admins        enable row level security;

drop policy if exists klipin_posts_select on public.posts;
create policy klipin_posts_select on public.posts for select to anon, authenticated
  using (u = false or o = (select auth.uid()) or (select public.is_admin()));

drop policy if exists klipin_posts_insert on public.posts;
create policy klipin_posts_insert on public.posts for insert to authenticated
  with check (o = (select auth.uid()) and a like (select auth.uid())::text || '/%');

drop policy if exists klipin_posts_update on public.posts;
create policy klipin_posts_update on public.posts for update to authenticated
  using (o = (select auth.uid()))
  with check (o = (select auth.uid()) and a like (select auth.uid())::text || '/%');

drop policy if exists klipin_posts_delete on public.posts;
create policy klipin_posts_delete on public.posts for delete to authenticated
  using (o = (select auth.uid()) or (select public.is_admin()));

drop policy if exists klipin_profiles_select on public.profiles;
create policy klipin_profiles_select on public.profiles for select to anon, authenticated
  using (true);

drop policy if exists klipin_profiles_insert on public.profiles;
create policy klipin_profiles_insert on public.profiles for insert to authenticated
  with check (id = (select auth.uid()));

drop policy if exists klipin_profiles_update on public.profiles;
create policy klipin_profiles_update on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy if exists klipin_settings_all on public.user_settings;
create policy klipin_settings_all on public.user_settings for all to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy if exists klipin_admins_select on public.admins;
create policy klipin_admins_select on public.admins for select to authenticated
  using (id = (select auth.uid()));

-- 4. Penyimpanan file (bucket media) ----------------------------------
-- Batas 5242880000 byte = 5000 MB per file.
-- Paket gratis Supabase hanya mengizinkan 50 MB per file. Untuk lebih dari itu, upgrade paket
-- lalu naikkan juga Storage > Settings > Global file size limit. Samakan angka ini dengan maxMB di config.js.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', true, 5242880000,
        array['image/png', 'image/jpeg', 'image/gif', 'image/webp', 'video/mp4', 'video/webm'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists klipin_media_insert on storage.objects;
create policy klipin_media_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- Supabase menghapus file lewat select + delete, jadi keduanya dibutuhkan.
drop policy if exists klipin_media_select on storage.objects;
create policy klipin_media_select on storage.objects for select to authenticated
  using (bucket_id = 'media'
         and ((storage.foldername(name))[1] = (select auth.uid())::text or (select public.is_admin())));

drop policy if exists klipin_media_delete on storage.objects;
create policy klipin_media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'media'
         and ((storage.foldername(name))[1] = (select auth.uid())::text or (select public.is_admin())));

-- 5. Realtime ---------------------------------------------------------

do $$ begin
  alter publication supabase_realtime add table public.posts;
exception when duplicate_object then null;
end $$;

do $$ begin
  alter publication supabase_realtime add table public.profiles;
exception when duplicate_object then null;
end $$;
