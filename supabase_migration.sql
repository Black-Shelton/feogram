-- FEOGRAM v2 — МИГРАЦИЯ (исправленный порядок)
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
  last_seen     timestamptz,
  nick_color    text,
  profile_color text,
  nick_emoji    text,
  created_at    timestamptz default now()
);

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
-- Must exist BEFORE the chat policies that reference it
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

-- Now add chat policies (chat_participants table exists now)
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
-- ГОТОВО! После регистрации на сайте стать владельцем:
--
-- UPDATE public.profiles
-- SET is_owner = true, is_admin = true
-- WHERE username = 'ТВОЙ_НИК';
--
-- ИЛИ войти с email: owner@feogram.com (авто-Owner)
-- ═══════════════════════════════════════════════════════════

-- ─── CHAT ADMINS (канальные/групповые администраторы) ───────
create table if not exists public.chat_admins (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  tag text default 'Админ',
  created_at timestamptz default now(),
  unique(chat_id, user_id)
);
alter table public.chat_admins enable row level security;
create policy "chat_admins_select" on public.chat_admins for select using (auth.role()='authenticated');
create policy "chat_admins_insert" on public.chat_admins for insert with check (auth.role()='authenticated');
create policy "chat_admins_delete" on public.chat_admins for delete using (auth.role()='authenticated');

-- ─── CHAT BANS (баны внутри канала/группы) ─────────────────
create table if not exists public.chat_bans (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz default now(),
  unique(chat_id, user_id)
);
alter table public.chat_bans enable row level security;
create policy "chat_bans_all" on public.chat_bans for all using (auth.role()='authenticated');

-- ─── Убедись что у chats есть description ──────────────────
-- (уже есть в основной миграции, эта строка для безопасности)
alter table public.chats add column if not exists description text;
alter table public.chats add column if not exists is_frozen boolean default false;
alter table public.chats add column if not exists is_verified boolean default false;
alter table public.profiles add column if not exists display_name text;
alter table public.profiles add column if not exists bio text;
alter table public.profiles add column if not exists nick_color text;
alter table public.profiles add column if not exists profile_color text;
alter table public.profiles add column if not exists nick_emoji text;
alter table public.profiles add column if not exists has_febait boolean default false;
alter table public.profiles add column if not exists is_verified boolean default false;
alter table public.profiles add column if not exists is_owner boolean default false;

-- ─── OFFICIAL CHANNEL (создаётся автоматически owner-ом) ──
-- Если хочешь создать вручную:
-- INSERT INTO public.chats (type, name, description, is_verified)
-- VALUES ('channel', 'FeoGram Official', '✓ Официальный Канал FeoGram.', true);

-- ─── SLUG для каналов/групп ──────────────────────────────────
alter table public.chats add column if not exists slug text unique;
create index if not exists idx_chats_slug on public.chats(slug);

-- Официальный канал FeoGram — создать вручную если нужно:
-- INSERT INTO public.chats (type, name, slug, description, is_verified)
-- VALUES ('channel', 'FeoGram Official', 'FeoGram_Official', '✓ Официальный Канал FeoGram.', true)
-- ON CONFLICT DO NOTHING;
