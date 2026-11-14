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

-- 1b. Kolom tambahan (aman untuk database lama) -----------------------

alter table public.posts
  add column if not exists cat      text   not null default 'lainnya'
    check (cat in ('musik', 'gaming', 'edukasi', 'vlog', 'olahraga', 'berita', 'komedi', 'teknologi', 'lainnya')),
  add column if not exists tags     text   not null default '' check (char_length(tags) <= 200),
  add column if not exists views    bigint not null default 0,
  add column if not exists likes    int    not null default 0,
  add column if not exists dislikes int    not null default 0;

alter table public.profiles
  add column if not exists handle text unique check (handle ~ '^[a-z0-9_]{3,20}$'),
  add column if not exists subs   int not null default 0;

create table if not exists public.reactions (
  post_id text not null references public.posts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  v       smallint not null check (v in (1, -1)),
  primary key (post_id, user_id)
);

create table if not exists public.subs (
  channel uuid not null references auth.users (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  primary key (channel, user_id),
  check (channel <> user_id)
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
grant select on public.reactions, public.subs to authenticated;

-- Angka views, like, dan subscriber hanya boleh diubah lewat fungsi di bawah.
revoke update on public.posts from authenticated;
grant update (ti, ds, cat, tags, u) on public.posts to authenticated;
revoke update on public.profiles from authenticated;
grant update (id, name, bio, handle) on public.profiles to authenticated;

alter table public.posts         enable row level security;
alter table public.profiles      enable row level security;
alter table public.user_settings enable row level security;
alter table public.admins        enable row level security;
alter table public.reactions     enable row level security;
alter table public.subs          enable row level security;

drop policy if exists klipin_posts_select on public.posts;
create policy klipin_posts_select on public.posts for select to anon, authenticated
  using (u = false or o = (select auth.uid()) or (select public.is_admin()));

drop policy if exists klipin_posts_insert on public.posts;
create policy klipin_posts_insert on public.posts for insert to authenticated
  with check (o = (select auth.uid()) and a like (select auth.uid())::text || '/%'
              and views = 0 and likes = 0 and dislikes = 0);

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
  with check (id = (select auth.uid()) and subs = 0);

drop policy if exists klipin_profiles_update on public.profiles;
create policy klipin_profiles_update on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy if exists klipin_settings_all on public.user_settings;
create policy klipin_settings_all on public.user_settings for all to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy if exists klipin_reactions_select on public.reactions;
create policy klipin_reactions_select on public.reactions for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists klipin_subs_select on public.subs;
create policy klipin_subs_select on public.subs for select to authenticated
  using (user_id = (select auth.uid()));

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

-- 6. Like, dislike, views, subscribe ----------------------------------

create or replace function public.react(p_id text, p_v smallint)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  me  uuid := auth.uid();
  cur smallint;
begin
  if me is null then raise exception 'login diperlukan' using errcode = '28000'; end if;
  select v into cur from public.reactions where post_id = p_id and user_id = me;
  if cur is not null then
    delete from public.reactions where post_id = p_id and user_id = me;
    update public.posts set likes = likes - (cur = 1)::int, dislikes = dislikes - (cur = -1)::int where id = p_id;
  end if;
  if p_v in (1, -1) and cur is distinct from p_v then
    insert into public.reactions (post_id, user_id, v) values (p_id, me, p_v);
    update public.posts set likes = likes + (p_v = 1)::int, dislikes = dislikes + (p_v = -1)::int where id = p_id;
  end if;
end $$;

create or replace function public.add_view(p_id text)
returns void
language sql security definer
set search_path = public
as $$ update public.posts set views = views + 1 where id = p_id $$;

create or replace function public.toggle_sub(p_channel uuid)
returns boolean
language plpgsql security definer
set search_path = public
as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'login diperlukan' using errcode = '28000'; end if;
  if p_channel = me then raise exception 'tidak bisa subscribe ke diri sendiri' using errcode = '22023'; end if;
  if exists (select 1 from public.subs where channel = p_channel and user_id = me) then
    delete from public.subs where channel = p_channel and user_id = me;
    update public.profiles set subs = greatest(subs - 1, 0) where id = p_channel;
    return false;
  end if;
  insert into public.subs (channel, user_id) values (p_channel, me);
  insert into public.profiles (id, subs) values (p_channel, 1)
    on conflict (id) do update set subs = public.profiles.subs + 1;
  return true;
end $$;

revoke all on function public.react(text, smallint) from public;
grant execute on function public.react(text, smallint) to authenticated;
revoke all on function public.toggle_sub(uuid) from public;
grant execute on function public.toggle_sub(uuid) to authenticated;
grant execute on function public.add_view(text) to anon, authenticated;
