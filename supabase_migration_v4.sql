-- FEOGRAM v3 — REACTIONS + PAID REACTIONS + CHANNEL BALANCE
-- Safe to re-run (idempotent)

-- ─── chats: paid_reactions flag ──────────────────────────────
alter table public.chats add column if not exists paid_reactions boolean default false;

-- ─── message_reactions ───────────────────────────────────────
create table if not exists public.message_reactions (
  id          uuid primary key default gen_random_uuid(),
  message_id  uuid not null references public.messages(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  emoji       text not null,
  is_anon     boolean default false,
  created_at  timestamptz default now(),
  unique(message_id, user_id, emoji)
);
alter table public.message_reactions enable row level security;

do $$ begin
  create policy "rx_select" on public.message_reactions
    for select using (auth.role() = 'authenticated');
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "rx_insert" on public.message_reactions
    for insert with check (auth.uid() = user_id);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "rx_delete_own" on public.message_reactions
    for delete using (auth.uid() = user_id);
exception when duplicate_object then null; end $$;

create index if not exists idx_rx_msg on public.message_reactions(message_id);

alter publication supabase_realtime add table public.message_reactions;

-- ─── paid_reactions ──────────────────────────────────────────
create table if not exists public.paid_reactions (
  id           uuid primary key default gen_random_uuid(),
  message_id   uuid not null references public.messages(id) on delete cascade,
  chat_id      uuid not null references public.chats(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  sender_name  text,
  amount       integer not null check(amount > 0),
  is_anon      boolean default false,
  created_at   timestamptz default now()
);
alter table public.paid_reactions enable row level security;

do $$ begin
  create policy "pr_select" on public.paid_reactions
    for select using (auth.role() = 'authenticated');
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "pr_insert" on public.paid_reactions
    for insert with check (auth.uid() = user_id);
exception when duplicate_object then null; end $$;

create index if not exists idx_pr_msg  on public.paid_reactions(message_id);
create index if not exists idx_pr_chat on public.paid_reactions(chat_id);

-- ─── channel_coin_balance ────────────────────────────────────
create table if not exists public.channel_coin_balance (
  id             uuid primary key default gen_random_uuid(),
  chat_id        uuid not null unique references public.chats(id) on delete cascade,
  total_coins    integer default 0,
  gifts_received jsonb  default '[]',
  updated_at     timestamptz default now()
);
alter table public.channel_coin_balance enable row level security;

do $$ begin
  create policy "ccb_select" on public.channel_coin_balance
    for select using (auth.role() = 'authenticated');
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "ccb_insert" on public.channel_coin_balance
    for insert with check (auth.role() = 'authenticated');
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "ccb_update" on public.channel_coin_balance
    for update using (auth.role() = 'authenticated');
exception when duplicate_object then null; end $$;

create index if not exists idx_ccb_chat on public.channel_coin_balance(chat_id);

-- ─── chats.slug — ensure unique index exists ─────────────────
create unique index if not exists idx_chats_slug_uniq on public.chats(slug)
  where slug is not null;

-- ═══════════════════════════════════════════════════════════
-- HOW TO TAG MESSAGES WITH data-msg-id:
-- The JS uses [data-msg-id] selectors. In your renderMessage()
-- function add:   el.setAttribute('data-msg-id', msg.id);
-- on the root message div.
-- ═══════════════════════════════════════════════════════════


-- ── v4 additions ──────────────────────────────────────────────

-- stories table
create table if not exists public.stories (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references public.profiles(id) on delete cascade,
  username         text,
  avatar_url       text,
  text             text,
  media_url        text,
  media_type       text,         -- 'image' | 'video'
  background       text,
  display_duration integer default 10,
  expires_at       timestamptz not null,
  created_at       timestamptz default now()
);
alter table public.stories enable row level security;
do $$ begin
  create policy "stories_select" on public.stories for select using (auth.role()='authenticated');
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "stories_insert" on public.stories for insert with check (auth.uid()=user_id);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "stories_delete" on public.stories for delete using (auth.uid()=user_id);
exception when duplicate_object then null; end $$;
create index if not exists idx_stories_user on public.stories(user_id);
create index if not exists idx_stories_expires on public.stories(expires_at);
alter publication supabase_realtime add table public.stories;

-- broadcasts table
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
do $$ begin
  create policy "bc_select" on public.broadcasts for select using (auth.role()='authenticated');
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "bc_insert" on public.broadcasts for insert with check (auth.role()='authenticated');
exception when duplicate_object then null; end $$;
alter publication supabase_realtime add table public.broadcasts;
