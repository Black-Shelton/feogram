-- FEOGRAM v3 — МИГРАЦИЯ (полная)
-- Supabase → SQL Editor → New Query → вставь всё → Run

-- ─── 1. PROFILES ───────────────────────────────────────────
create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  username      text unique not null,
  email         text,
  display_name  text,
  bio           text,
  coins         integer default 100,
  gifts         text[]  default '{}',
  is_owner      boolean default false,
  is_admin      boolean default false,
  is_banned     boolean default false,
  is_scam       boolean default false,
  is_verified   boolean default false,
  has_febait    boolean default false,
  ban_reason    text,
  banned_at     timestamptz,
  ban_until     timestamptz,       -- NEW: временный бан
  avatar_url    text,              -- NEW: фото профиля (base64 или URL)
  last_seen     timestamptz,
  nick_color    text,
  profile_color text,
  nick_emoji    text,
  created_at    timestamptz default now()
);

-- Если таблица уже существует — добавь колонки:
alter table public.profiles add column if not exists ban_until timestamptz;
alter table public.profiles add column if not exists avatar_url text;

alter table public.profiles enable row level security;

create policy "profiles_select" on public.profiles
  for select using (auth.role() = 'authenticated');

create policy "profiles_insert" on public.profiles
  for insert with check (auth.uid() = id);

create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id);

create policy "profiles_update_admin" on public.profiles
  for update using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (p.is_admin = true or p.is_owner = true)
    )
  );

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, username, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', split_part(new.email,'@',1)),
    new.email
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ─── 2. CHATS ──────────────────────────────────────────────
create table if not exists public.chats (
  id          uuid primary key default gen_random_uuid(),
  type        text not null check (type in ('dm','group','channel')),
  name        text,
  description text,
  is_verified boolean default false,
  is_frozen   boolean default false,
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz default now()
);

alter table public.chats enable row level security;

-- ─── 3. CHAT_PARTICIPANTS ───────────────────────────────────
create table if not exists public.chat_participants (
  id        uuid primary key default gen_random_uuid(),
  chat_id   uuid not null references public.chats(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz default now(),
  unique(chat_id, user_id)
);

alter table public.chat_participants enable row level security;

create policy "parts_select" on public.chat_participants
  for select using (user_id = auth.uid());

create policy "parts_insert" on public.chat_participants
  for insert with check (auth.role() = 'authenticated');

-- Chat policies
create policy "chats_select" on public.chats
  for select using (
    exists (
      select 1 from public.chat_participants cp
      where cp.chat_id = chats.id
        and cp.user_id = auth.uid()
    )
  );

create policy "chats_insert" on public.chats
  for insert with check (auth.role() = 'authenticated');

create policy "chats_update_admin" on public.chats
  for update using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (p.is_admin = true or p.is_owner = true)
    )
  );

-- Allow creator to update their own channel/group
create policy "chats_update_creator" on public.chats
  for update using (created_by = auth.uid());

-- ─── 4. MESSAGES ───────────────────────────────────────────
create table if not exists public.messages (
  id          uuid primary key default gen_random_uuid(),
  chat_id     uuid not null references public.chats(id) on delete cascade,
  sender_id   uuid references public.profiles(id) on delete set null,
  sender_name text,
  content     text,
  type        text default 'text'
              check (type in ('text','gift','sticker','gif','system')),
  created_at  timestamptz default now()
);

alter table public.messages enable row level security;

create policy "msgs_select" on public.messages
  for select using (
    exists (
      select 1 from public.chat_participants cp
      where cp.chat_id = messages.chat_id
        and cp.user_id = auth.uid()
    )
  );

create policy "msgs_insert" on public.messages
  for insert with check (
    exists (
      select 1 from public.chat_participants cp
      where cp.chat_id = messages.chat_id
        and cp.user_id = auth.uid()
    )
  );

-- Realtime for messages
alter publication supabase_realtime add table public.messages;

-- ─── 5. BLACKLIST ───────────────────────────────────────────
create table if not exists public.blacklist (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz default now(),
  unique(user_id, blocked_id)
);

alter table public.blacklist enable row level security;

create policy "bl_all" on public.blacklist
  for all using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ─── 6. INDEXES ────────────────────────────────────────────
create index if not exists idx_msgs_chat    on public.messages(chat_id);
create index if not exists idx_msgs_time    on public.messages(created_at desc);
create index if not exists idx_parts_user   on public.chat_participants(user_id);
create index if not exists idx_parts_chat   on public.chat_participants(chat_id);
create index if not exists idx_prof_uname   on public.profiles(username);
create index if not exists idx_bl_user      on public.blacklist(user_id);

-- ═══════════════════════════════════════════════════════════
-- ПОСЛЕ РЕГИСТРАЦИИ — стать Owner:
--
-- UPDATE public.profiles
-- SET is_owner = true, is_admin = true
-- WHERE username = 'ТВОЙ_НИК';
-- ═══════════════════════════════════════════════════════════
