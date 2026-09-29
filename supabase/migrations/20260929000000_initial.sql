-- Online mode: accounts, one save per player, server-only writes.
--
-- Players sign in with email; the only other thing stored about them is a
-- display name they choose. No real names, birthdays or photos. Deleting the
-- auth user deletes everything below (on delete cascade).

create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 20),
  created_at timestamptz not null default now()
);

-- One row per player holding the whole save (same format as single-player).
-- `revision` guards against two requests overwriting each other.
create table public.saves (
  user_id uuid primary key references auth.users (id) on delete cascade,
  save_version integer not null,
  data jsonb not null,
  revision bigint not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.saves enable row level security;

-- Players may read their own rows. There are deliberately no insert, update
-- or delete policies: only the server functions (service role) write, after
-- checking the game rules.
create policy "Players read their own profile"
  on public.profiles for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "Players read their own save"
  on public.saves for select to authenticated
  using ((select auth.uid()) = user_id);

revoke insert, update, delete on public.profiles from anon, authenticated;
revoke insert, update, delete on public.saves from anon, authenticated;
revoke all on public.profiles from anon;
revoke all on public.saves from anon;
