-- FEOGRAM v2 — ПОЛНАЯ МИГРАЦИЯ 2026 (FIXED)
-- Supabase → SQL Editor → Run All
-- Fix: chat_participants создаётся ДО политик chats,
--      которые на неё ссылаются (42P01 resolved)

-- ─── 1. PROFILES ────────────────────────────────────────────────
create table if not exists public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  username text unique not null,
  email text,
  coins integer default 100,
  gifts text[] default '{}',
  is_owner boolean default false,
  is_admin boolean default false,
  is_banned boolean default false,
  is_scam boolean default false,
  is_verified boolean default false,
  ban_reason text,
  banned_at timestamptz,
  last_seen timestamptz,
  has_febait boolean default false,
  nick_color text,
  profile_color text,
  nick_emoji text,
  display_name text,
  bio text,
  created_at timestamptz default now()
);

alter table public.profiles enable row level security;

create policy "View all profiles"
  on public.profiles for select
  using (auth.role() = 'authenticated');

create policy "Update own profile"
  on public.profiles for update
  using (auth.uid() = id);

create policy "Insert own profile"
  on public.profiles for insert
  with check (auth.uid() = id);

create policy "Admin update any"
  on public.profiles for update
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (p.is_admin = true or p.is_owner = true)
    )
  );

-- ─── 2. AUTO-PROFILE TRIGGER ────────────────────────────────────
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, username, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', split_part(new.email,'@',1)),
    new.email
  );
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ─── 3. CHATS (без политик на chat_participants пока) ───────────
create table if not exists public.chats (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('dm','group','channel')),
  name text,
  description text,
  is_verified boolean default false,
  is_frozen boolean default false,
  created_by uuid references public.profiles(id),
  created_at timestamptz default now()
);

alter table public.chats enable row level security;

-- ─── 4. CHAT_PARTICIPANTS — СНАЧАЛА ТАБЛИЦА ─────────────────────
-- Политики chats ссылаются на эту таблицу → она должна быть первой
create table if not exists public.chat_participants (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid references public.chats(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  joined_at timestamptz default now(),
  unique(chat_id, user_id)
);

alter table public.chat_participants enable row level security;

create policy "View own participations"
  on public.chat_participants for select
  using (user_id = auth.uid());

create policy "Join chats"
  on public.chat_participants for insert
  with check (auth.role() = 'authenticated');

-- ─── 5. ПОЛИТИКИ CHATS — теперь chat_participants уже существует ─
create policy "Participants view chats"
  on public.chats for select
  using (
    exists (
      select 1 from public.chat_participants
      where chat_id = chats.id and user_id = auth.uid()
    )
  );

create policy "Auth create chats"
  on public.chats for insert
  with check (auth.role() = 'authenticated');

create policy "Admin update chats"
  on public.chats for update
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (p.is_admin = true or p.is_owner = true)
    )
  );

-- ─── 6. MESSAGES ────────────────────────────────────────────────
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid references public.chats(id) on delete cascade,
  sender_id uuid references public.profiles(id),
  sender_name text,
  content text,
  type text default 'text' check (type in ('text','gift','sticker','gif','system')),
  created_at timestamptz default now()
);

alter table public.messages enable row level security;

create policy "Participants read msgs"
  on public.messages for select
  using (
    exists (
      select 1 from public.chat_participants
      where chat_id = messages.chat_id and user_id = auth.uid()
    )
  );

create policy "Participants send msgs"
  on public.messages for insert
  with check (
    exists (
      select 1 from public.chat_participants
      where chat_id = messages.chat_id and user_id = auth.uid()
    )
  );

alter publication supabase_realtime add table public.messages;

-- ─── 7. BLACKLIST ────────────────────────────────────────────────
create table if not exists public.blacklist (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade,
  blocked_id uuid references public.profiles(id) on delete cascade,
  created_at timestamptz default now(),
  unique(user_id, blocked_id)
);

alter table public.blacklist enable row level security;

create policy "Manage own blacklist"
  on public.blacklist for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ─── 8. ИНДЕКСЫ ─────────────────────────────────────────────────
create index if not exists idx_messages_chat     on public.messages(chat_id);
create index if not exists idx_messages_time     on public.messages(created_at desc);
create index if not exists idx_parts_user        on public.chat_participants(user_id);
create index if not exists idx_parts_chat        on public.chat_participants(chat_id);
create index if not exists idx_profiles_username on public.profiles(username);
create index if not exists idx_bl_user           on public.blacklist(user_id);

-- ═══════════════════════════════════════════
-- АККАУНТ ВЛАДЕЛЬЦА (2026):
--   Email:    owner@feogram.com
--   Password: FeoGram2026!Owner
-- После входа — автоматически Owner.
-- ИЛИ вручную после регистрации:
-- UPDATE public.profiles SET is_owner=true, is_admin=true WHERE username='твойНик';
-- ═══════════════════════════════════════════
