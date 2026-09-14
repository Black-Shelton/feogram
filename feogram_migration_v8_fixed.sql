-- ═══════════════════════════════════════════════════════════════
-- FEOGRAM — МИГРАЦИЯ v8 (FULLY FIXED)
-- Исправлено: ERROR 42710 — relation already member of publication
-- Исправлено: дублирующиеся ADD COLUMN на таблицах уже с колонками
-- Исправлено: порядок DROP/CREATE политик
-- Supabase → SQL Editor → New Query → Run
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. PROFILES ─────────────────────────────────────────────
create table if not exists public.profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  username        text unique not null,
  display_name    text,
  email           text,
  bio             text,
  avatar_url      text,
  coins           integer default 0,
  gifts           text[]  default '{}',
  is_owner        boolean default false,
  is_second_owner boolean default false,
  is_admin        boolean default false,
  is_banned       boolean default false,
  is_scam         boolean default false,
  is_premium      boolean default false,
  has_febait      boolean default false,
  is_verified     boolean default false,
  has_verified    boolean default false,
  is_frozen       boolean default false,
  can_pin         boolean default false,
  ban_reason      text,
  banned_at       timestamptz,
  ban_until       timestamptz,
  last_seen       timestamptz default now(),
  nick_color      text,
  profile_color   text,
  nick_emoji      text,
  promoted_by     uuid,
  created_at      timestamptz default now()
);

-- Колонки (безопасно — ADD COLUMN IF NOT EXISTS)
alter table public.profiles add column if not exists display_name    text;
alter table public.profiles add column if not exists is_owner        boolean default false;
alter table public.profiles add column if not exists is_admin        boolean default false;
alter table public.profiles add column if not exists is_second_owner boolean default false;
alter table public.profiles add column if not exists is_scam         boolean default false;
alter table public.profiles add column if not exists is_banned       boolean default false;
alter table public.profiles add column if not exists is_frozen       boolean default false;
alter table public.profiles add column if not exists ban_reason      text;
alter table public.profiles add column if not exists last_seen       timestamptz default now();
alter table public.profiles add column if not exists is_premium      boolean default false;
alter table public.profiles add column if not exists banned_at       timestamptz;
alter table public.profiles add column if not exists can_pin         boolean default false;
alter table public.profiles add column if not exists email           text;
alter table public.profiles add column if not exists bio             text;
alter table public.profiles add column if not exists avatar_url      text;
alter table public.profiles add column if not exists ban_until       timestamptz;
alter table public.profiles add column if not exists is_verified     boolean default false;
alter table public.profiles add column if not exists has_verified    boolean default false;
alter table public.profiles add column if not exists has_febait      boolean default false;
alter table public.profiles add column if not exists coins           integer default 0;
alter table public.profiles add column if not exists gifts           text[] default '{}';
alter table public.profiles add column if not exists nick_color      text;
alter table public.profiles add column if not exists profile_color   text;
alter table public.profiles add column if not exists nick_emoji      text;
alter table public.profiles add column if not exists promoted_by     uuid;
alter table public.profiles add column if not exists created_at      timestamptz default now();

alter table public.profiles enable row level security;

drop policy if exists "profiles_select"     on public.profiles;
drop policy if exists "profiles_insert"     on public.profiles;
drop policy if exists "profiles_update_own" on public.profiles;

create policy "profiles_select" on public.profiles
  for select using (auth.role() = 'authenticated');

create policy "profiles_insert" on public.profiles
  for insert with check (auth.uid() = id);

create policy "profiles_update_own" on public.profiles
  for update using (
    auth.uid() = id
    or exists (
      select 1 from public.profiles p2
      where p2.id = auth.uid()
        and (p2.is_admin = true or p2.is_owner = true or p2.is_second_owner = true)
    )
  );

-- ─── TRIGGER: auto-create profile on signup ──────────────────
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
declare
  v_username text;
  v_display  text;
  v_email    text;
begin
  v_email    := new.email;
  v_username := coalesce(
    new.raw_user_meta_data->>'username',
    regexp_replace(split_part(new.email,'@',1),'[^a-zA-Z0-9_.\-]','_','g')
  );
  v_display  := coalesce(new.raw_user_meta_data->>'display_name', v_username);
  if exists(select 1 from public.profiles where username = v_username) then
    v_username := v_username || '_' || substr(new.id::text,1,4);
  end if;
  insert into public.profiles (id, username, display_name, email, coins, gifts)
  values (new.id, v_username, v_display, v_email, 0, '{}')
  on conflict (id) do update
    set display_name = coalesce(public.profiles.display_name, excluded.display_name),
        email        = coalesce(public.profiles.email, excluded.email);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ─── 2. CHATS ────────────────────────────────────────────────
create table if not exists public.chats (
  id               uuid primary key default gen_random_uuid(),
  type             text not null check (type in ('dm','group','channel')),
  name             text,
  description      text,
  slug             text,
  created_by       uuid references public.profiles(id) on delete set null,
  has_verified     boolean default false,
  is_verified      boolean default false,
  is_frozen        boolean default false,
  paid_reactions   boolean default false,
  invite_code      text,
  coin_balance     integer default 0,
  allow_gifts      boolean default false,
  pinned_msg_id      uuid,
  pinned_msg_content text,
  pinned_msg_sender  text,
  discussion_chat_id uuid,
  discussion_for     uuid,
  created_at       timestamptz default now()
);

alter table public.chats add column if not exists is_frozen           boolean default false;
alter table public.chats add column if not exists is_verified         boolean default false;
alter table public.chats add column if not exists paid_reactions      boolean default false;
alter table public.chats add column if not exists invite_code         text;
alter table public.chats add column if not exists coin_balance        integer default 0;
alter table public.chats add column if not exists allow_gifts         boolean default false;
alter table public.chats add column if not exists pinned_msg_id       uuid;
alter table public.chats add column if not exists pinned_msg_content  text;
alter table public.chats add column if not exists pinned_msg_sender   text;
alter table public.chats add column if not exists discussion_chat_id  uuid;
alter table public.chats add column if not exists discussion_for      uuid;

alter table public.chats enable row level security;

create unique index if not exists idx_chats_slug_uniq   on public.chats(slug)        where slug is not null;
create unique index if not exists idx_chats_invite_uniq on public.chats(invite_code) where invite_code is not null;

-- ─── 3. CHAT_PARTICIPANTS (before chats policy!) ─────────────
create table if not exists public.chat_participants (
  id        uuid primary key default gen_random_uuid(),
  chat_id   uuid not null references public.chats(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  role      text default 'member' check (role in ('member','moderator','admin')),
  is_admin  boolean default false,
  can_pin   boolean default false,
  joined_at timestamptz default now(),
  unique(chat_id, user_id)
);

alter table public.chat_participants add column if not exists is_admin boolean default false;
alter table public.chat_participants add column if not exists can_pin  boolean default false;

alter table public.chat_participants enable row level security;

drop policy if exists "participants_select" on public.chat_participants;
drop policy if exists "participants_insert" on public.chat_participants;
drop policy if exists "participants_delete" on public.chat_participants;

create policy "participants_select" on public.chat_participants
  for select using (user_id = auth.uid());

create policy "participants_insert" on public.chat_participants
  for insert with check (auth.role() = 'authenticated');

create policy "participants_delete" on public.chat_participants
  for delete using (
    user_id = auth.uid()
    or exists(select 1 from public.profiles p where p.id = auth.uid() and (p.is_admin or p.is_owner))
  );

-- ─── 4. CHATS policies (now chat_participants exists) ─────────
drop policy if exists "chats_select"                on public.chats;
drop policy if exists "chats_insert"                on public.chats;
drop policy if exists "chats_update"                on public.chats;
drop policy if exists "chat admins can pin messages" on public.chats;

create policy "chats_select" on public.chats
  for select using (
    type in ('channel','group')
    or exists (
      select 1 from public.chat_participants cp
      where cp.chat_id = chats.id and cp.user_id = auth.uid()
    )
  );

create policy "chats_insert" on public.chats
  for insert with check (auth.role() = 'authenticated');

create policy "chats_update" on public.chats
  for update using (
    created_by = auth.uid()
    or exists (
      select 1 from public.chat_participants
      where chat_id = chats.id and user_id = auth.uid() and is_admin = true
    )
    or exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (p.is_owner = true or p.is_second_owner = true or p.is_admin = true)
    )
  );

-- ─── 5. MESSAGES ─────────────────────────────────────────────
create table if not exists public.messages (
  id                  uuid primary key default gen_random_uuid(),
  chat_id             uuid not null references public.chats(id) on delete cascade,
  sender_id           uuid references public.profiles(id) on delete set null,
  sender_name         text,
  content             text,
  type                text default 'text'
                      check (type in ('text','gift','sticker','gif','system','image','video','audio','file','forward')),
  sticker_url         text,
  forwarded_from_id   uuid,
  forwarded_from_name text,
  forwarded_from_chat uuid,
  created_at          timestamptz default now()
);

alter table public.messages add column if not exists sticker_url         text;
alter table public.messages add column if not exists forwarded_from_id   uuid;
alter table public.messages add column if not exists forwarded_from_name text;
alter table public.messages add column if not exists forwarded_from_chat uuid;

alter table public.messages enable row level security;

drop policy if exists "messages_select" on public.messages;
drop policy if exists "messages_insert" on public.messages;

create policy "messages_select" on public.messages
  for select using (
    exists (
      select 1 from public.chat_participants cp
      where cp.chat_id = messages.chat_id and cp.user_id = auth.uid()
    )
    or exists (
      select 1 from public.chats c
      where c.id = messages.chat_id and c.type in ('channel','group')
    )
  );

create policy "messages_insert" on public.messages
  for insert with check (
    sender_id is null
    or exists (
      select 1 from public.chat_participants cp
      where cp.chat_id = messages.chat_id and cp.user_id = auth.uid()
    )
  );

-- ─── 6. BLACKLIST ────────────────────────────────────────────
create table if not exists public.blacklist (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz default now(),
  unique(user_id, blocked_id)
);

alter table public.blacklist enable row level security;

drop policy if exists "blacklist_all" on public.blacklist;

create policy "blacklist_all" on public.blacklist
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ─── 7. STICKERS ─────────────────────────────────────────────
create table if not exists public.stickers (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid references public.profiles(id) on delete cascade,
  name        text not null,
  url         text not null,
  is_animated boolean default false,
  is_public   boolean default false,
  created_at  timestamptz default now()
);

alter table public.stickers enable row level security;

drop policy if exists "stickers_select" on public.stickers;
drop policy if exists "stickers_insert" on public.stickers;
drop policy if exists "stickers_delete" on public.stickers;

create policy "stickers_select" on public.stickers
  for select using (is_public = true or owner_id = auth.uid());

create policy "stickers_insert" on public.stickers
  for insert with check (owner_id = auth.uid());

create policy "stickers_delete" on public.stickers
  for delete using (owner_id = auth.uid());

-- ─── 8. MESSAGE REACTIONS ────────────────────────────────────
create table if not exists public.message_reactions (
  id         uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  emoji      text not null,
  is_anon    boolean default false,
  created_at timestamptz default now(),
  unique(message_id, user_id, emoji)
);

alter table public.message_reactions enable row level security;

drop policy if exists "rx_select" on public.message_reactions;
drop policy if exists "rx_insert" on public.message_reactions;
drop policy if exists "rx_delete" on public.message_reactions;

create policy "rx_select" on public.message_reactions
  for select using (auth.role() = 'authenticated');

create policy "rx_insert" on public.message_reactions
  for insert with check (auth.uid() = user_id);

create policy "rx_delete" on public.message_reactions
  for delete using (auth.uid() = user_id);

-- ─── 9. PAID REACTIONS ───────────────────────────────────────
create table if not exists public.paid_reactions (
  id          uuid primary key default gen_random_uuid(),
  message_id  uuid not null references public.messages(id) on delete cascade,
  chat_id     uuid not null references public.chats(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  sender_name text,
  amount      integer not null check (amount > 0),
  is_anon     boolean default false,
  created_at  timestamptz default now()
);

alter table public.paid_reactions enable row level security;

drop policy if exists "pr_select" on public.paid_reactions;
drop policy if exists "pr_insert" on public.paid_reactions;

create policy "pr_select" on public.paid_reactions
  for select using (auth.role() = 'authenticated');

create policy "pr_insert" on public.paid_reactions
  for insert with check (auth.uid() = user_id);

-- ─── 10. CHANNEL COIN BALANCE ────────────────────────────────
create table if not exists public.channel_coin_balance (
  id             uuid primary key default gen_random_uuid(),
  chat_id        uuid not null unique references public.chats(id) on delete cascade,
  total_coins    integer default 0,
  gifts_received jsonb   default '[]',
  updated_at     timestamptz default now()
);

alter table public.channel_coin_balance enable row level security;

drop policy if exists "ccb_select" on public.channel_coin_balance;
drop policy if exists "ccb_insert" on public.channel_coin_balance;
drop policy if exists "ccb_update" on public.channel_coin_balance;

create policy "ccb_select" on public.channel_coin_balance
  for select using (auth.role() = 'authenticated');

create policy "ccb_insert" on public.channel_coin_balance
  for insert with check (auth.role() = 'authenticated');

create policy "ccb_update" on public.channel_coin_balance
  for update using (auth.role() = 'authenticated');

-- ─── 11. WITHDRAWALS ─────────────────────────────────────────
create table if not exists public.withdrawals (
  id         uuid primary key default gen_random_uuid(),
  chat_id    uuid references public.chats(id) on delete set null,
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  amount     integer not null check (amount > 0),
  type       text not null check (type in ('coins','gift')),
  gift_id    text,
  status     text default 'pending' check (status in ('pending','approved','rejected')),
  note       text,
  created_at timestamptz default now()
);

alter table public.withdrawals enable row level security;

drop policy if exists "wd_own"   on public.withdrawals;
drop policy if exists "wd_admin" on public.withdrawals;

create policy "wd_own" on public.withdrawals
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy "wd_admin" on public.withdrawals
  for select using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and (p.is_admin or p.is_owner))
  );

-- ─── 12. STORIES ─────────────────────────────────────────────
create table if not exists public.stories (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references public.profiles(id) on delete cascade,
  username         text,
  avatar_url       text,
  text             text,
  media_url        text,
  media_type       text,
  background       text,
  display_duration integer default 10,
  expires_at       timestamptz not null,
  created_at       timestamptz default now()
);

alter table public.stories enable row level security;

drop policy if exists "stories_select" on public.stories;
drop policy if exists "stories_insert" on public.stories;
drop policy if exists "stories_delete" on public.stories;

create policy "stories_select" on public.stories
  for select using (auth.role() = 'authenticated');

create policy "stories_insert" on public.stories
  for insert with check (auth.uid() = user_id);

create policy "stories_delete" on public.stories
  for delete using (auth.uid() = user_id);

-- ─── 13. BROADCASTS ──────────────────────────────────────────
create table if not exists public.broadcasts (
  id           uuid primary key default gen_random_uuid(),
  created_by   uuid references public.profiles(id) on delete set null,
  text         text,
  emoji        text,
  duration_sec integer default 30,
  expires_at   timestamptz not null,
  created_at   timestamptz default now()
);

alter table public.broadcasts enable row level security;

drop policy if exists "bc_select" on public.broadcasts;
drop policy if exists "bc_insert" on public.broadcasts;

create policy "bc_select" on public.broadcasts
  for select using (auth.role() = 'authenticated');

create policy "bc_insert" on public.broadcasts
  for insert with check (auth.role() = 'authenticated');

-- ─── 14. USER FONTS ──────────────────────────────────────────
create table if not exists public.user_fonts (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references public.profiles(id) on delete cascade,
  name       text not null,
  url        text not null,
  css_family text not null,
  created_at timestamptz default now()
);

alter table public.user_fonts enable row level security;

drop policy if exists "fonts_select" on public.user_fonts;
drop policy if exists "fonts_insert" on public.user_fonts;
drop policy if exists "fonts_delete" on public.user_fonts;

create policy "fonts_select" on public.user_fonts
  for select using (user_id = auth.uid());

create policy "fonts_insert" on public.user_fonts
  for insert with check (user_id = auth.uid());

create policy "fonts_delete" on public.user_fonts
  for delete using (user_id = auth.uid());

-- ─── 15. ACTION LOGS ─────────────────────────────────────────
create table if not exists public.action_logs (
  id          uuid primary key default gen_random_uuid(),
  actor_id    uuid references public.profiles(id) on delete set null,
  actor_name  text,
  action      text not null,
  target_id   uuid,
  target_name text,
  details     jsonb default '{}',
  created_at  timestamptz default now()
);

alter table public.action_logs enable row level security;

drop policy if exists "logs_select_admin" on public.action_logs;
drop policy if exists "logs_insert"       on public.action_logs;

create policy "logs_select_admin" on public.action_logs
  for select using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (p.is_admin = true or p.is_owner = true or p.is_second_owner = true)
    )
  );

create policy "logs_insert" on public.action_logs
  for insert with check (auth.role() = 'authenticated');

-- ═══════════════════════════════════════════════════════════════
-- ─── 16. REALTIME — ИСПРАВЛЕННЫЙ БЛОК ────────────────────────
-- ПРОБЛЕМА: "relation already member of publication" (ERROR 42710)
-- ПРИЧИНА:  ALTER PUBLICATION ADD TABLE падает если таблица уже
--           добавлена в публикацию (например при повторном запуске
--           миграции или если Supabase добавил её автоматически).
-- РЕШЕНИЕ:  Проверяем pg_publication_tables перед каждым ADD TABLE.
--           Используем анонимный DO-блок — он поддерживается в
--           Supabase SQL Editor (в отличие от DO$$EXCEPTION в политиках).
-- ═══════════════════════════════════════════════════════════════

do $$
declare
  t text;
  tables text[] := array[
    'messages',
    'message_reactions',
    'paid_reactions',
    'stories',
    'broadcasts',
    'action_logs'
  ];
begin
  foreach t in array tables loop
    -- Добавляем таблицу только если её ещё нет в публикации
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I', t
      );
    end if;
  end loop;
end;
$$;

-- ─── 17. INDEXES ─────────────────────────────────────────────
create index if not exists idx_messages_chat_id      on public.messages(chat_id);
create index if not exists idx_messages_created_at   on public.messages(created_at desc);
create index if not exists idx_parts_user_id         on public.chat_participants(user_id);
create index if not exists idx_parts_chat_id         on public.chat_participants(chat_id);
create index if not exists idx_profiles_username     on public.profiles(username);
create index if not exists idx_profiles_username_low on public.profiles(lower(username));
create index if not exists idx_profiles_last_seen    on public.profiles(last_seen desc);
create index if not exists idx_blacklist_user_id     on public.blacklist(user_id);
create index if not exists idx_stickers_owner        on public.stickers(owner_id);
create index if not exists idx_rx_msg                on public.message_reactions(message_id);
create index if not exists idx_pr_msg                on public.paid_reactions(message_id);
create index if not exists idx_pr_chat               on public.paid_reactions(chat_id);
create index if not exists idx_ccb_chat              on public.channel_coin_balance(chat_id);
create index if not exists idx_stories_user          on public.stories(user_id);
create index if not exists idx_stories_expires       on public.stories(expires_at);
create index if not exists idx_wd_owner              on public.withdrawals(owner_id);
create index if not exists idx_action_logs_created   on public.action_logs(created_at desc);
create index if not exists idx_action_logs_actor     on public.action_logs(actor_id);
create index if not exists idx_user_fonts_user       on public.user_fonts(user_id);

-- ═══════════════════════════════════════════════════════════════
-- ГОТОВО. Миграция v8 идемпотентна — можно запускать повторно.
-- owner@feogram.com получит is_owner автоматически через код.
-- ═══════════════════════════════════════════════════════════════
