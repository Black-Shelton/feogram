-- Запусти ПЕРВЫМ если старая миграция частично прошла
drop table if exists public.blacklist cascade;
drop table if exists public.messages cascade;
drop table if exists public.chat_participants cascade;
drop table if exists public.chats cascade;
drop table if exists public.profiles cascade;
drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_user();
