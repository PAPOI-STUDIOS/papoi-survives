-- PAPOI Survives · esquema online (v1.5)
-- Ejecutar en Supabase → SQL Editor (en orden: 001 y luego 002).
-- Crea tablas nuevas; no borra nada existente.

-- Utilidad: updated_at siempre con hora del servidor
create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin new.updated_at = now(); return new; end $$;

-- 1) PERFILES (nombre público de cada cuenta)
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null,
  created_at timestamptz not null default now(),
  constraint profiles_username_format check (username ~ '^[A-Za-z0-9_]{3,16}$')
);
create unique index profiles_username_lower_idx on public.profiles (lower(username));
alter table public.profiles enable row level security;
create policy profiles_select_auth on public.profiles for select to authenticated using (true);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username) values (new.id, new.raw_user_meta_data->>'username');
  return new;
end $$;
revoke all on function public.handle_new_user() from public, anon, authenticated;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- 2) PROGRESO EN LA NUBE (privado: solo su dueño lo ve y lo edita)
create table public.player_saves (
  user_id uuid primary key references auth.users(id) on delete cascade,
  stats jsonb not null default '{}'::jsonb check (octet_length(stats::text) < 262144),
  updated_at timestamptz not null default now()
);
alter table public.player_saves enable row level security;
create policy saves_select_own on public.player_saves for select to authenticated using (user_id = (select auth.uid()));
create policy saves_insert_own on public.player_saves for insert to authenticated with check (user_id = (select auth.uid()));
create policy saves_update_own on public.player_saves for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create trigger saves_touch before update on public.player_saves
  for each row execute function public.touch_updated_at();

-- 3) PARTIDAS TERMINADAS (ranking). Nadie inserta directo: solo vía submit_run()
create table public.runs (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  username text not null,
  score bigint not null check (score >= 0),
  wave int not null check (wave between 1 and 1000),
  kills int not null check (kills >= 0),
  difficulty text not null check (difficulty in ('easy','normal','hard')),
  class text,
  map_id text,
  mode text not null check (mode in ('solo','coop')),
  survival_seconds int check (survival_seconds >= 0),
  created_at timestamptz not null default now()
);
create index runs_diff_score_idx on public.runs (difficulty, score desc);
create index runs_user_created_idx on public.runs (user_id, created_at desc);
alter table public.runs enable row level security;
create policy runs_select_auth on public.runs for select to authenticated using (true);

create or replace function public.submit_run(
  p_score bigint, p_wave int, p_kills int, p_difficulty text,
  p_class text, p_map text, p_mode text, p_seconds int)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_name text;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if p_score < 0 or p_score > 100000000 or p_wave < 1 or p_wave > 1000
     or p_kills < 0 or p_kills > 1000000 then
    raise exception 'valores fuera de rango';
  end if;
  if exists (select 1 from public.runs where user_id = v_uid and created_at > now() - interval '10 seconds') then
    raise exception 'demasiado rapido';
  end if;
  select username into v_name from public.profiles where id = v_uid;
  if v_name is null then raise exception 'sin perfil'; end if;
  insert into public.runs (user_id, username, score, wave, kills, difficulty, class, map_id, mode, survival_seconds)
  values (v_uid, v_name, p_score, p_wave, p_kills, p_difficulty, left(p_class,20), left(p_map,20), p_mode, p_seconds);
end $$;
revoke all on function public.submit_run(bigint,int,int,text,text,text,text,int) from public, anon;
grant execute on function public.submit_run(bigint,int,int,text,text,text,text,int) to authenticated;

-- Mejor partida de cada jugador por dificultad
create or replace function public.top_runs(p_difficulty text, p_limit int default 20)
returns table (username text, score bigint, wave int, kills int, class text, map_id text, mode text, created_at timestamptz)
language sql stable set search_path = public as $$
  select t.username, t.score, t.wave, t.kills, t.class, t.map_id, t.mode, t.created_at
  from (
    select distinct on (r.user_id) r.*
    from public.runs r where r.difficulty = p_difficulty
    order by r.user_id, r.score desc, r.created_at asc
  ) t
  order by t.score desc, t.created_at asc
  limit least(greatest(p_limit,1),50)
$$;
revoke all on function public.top_runs(text,int) from public, anon;
grant execute on function public.top_runs(text,int) to authenticated;

-- 4) SALAS ONLINE (lista pública; la partida en sí va por PeerJS/WebRTC)
create table public.rooms (
  code text primary key check (code ~ '^[A-Z0-9]{5}$'),
  host_id uuid not null unique references auth.users(id) on delete cascade,
  host_name text not null,
  map_id text not null default 'principal',
  status text not null default 'open' check (status in ('open','playing')),
  players int not null default 1 check (players between 1 and 4),
  max_players int not null default 4 check (max_players between 2 and 4),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.rooms enable row level security;
create policy rooms_select_auth on public.rooms for select to authenticated using (true);
create policy rooms_update_host on public.rooms for update to authenticated
  using (host_id = (select auth.uid())) with check (host_id = (select auth.uid()));
create policy rooms_delete_host on public.rooms for delete to authenticated using (host_id = (select auth.uid()));
create trigger rooms_touch before update on public.rooms
  for each row execute function public.touch_updated_at();

create or replace function public.create_room(p_code text, p_map text)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_name text;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select username into v_name from public.profiles where id = v_uid;
  if v_name is null then raise exception 'sin perfil'; end if;
  delete from public.rooms where updated_at < now() - interval '90 seconds';
  delete from public.rooms where host_id = v_uid;
  insert into public.rooms (code, host_id, host_name, map_id)
  values (upper(p_code), v_uid, v_name, coalesce(p_map,'principal'));
end $$;
revoke all on function public.create_room(text,text) from public, anon;
grant execute on function public.create_room(text,text) to authenticated;
