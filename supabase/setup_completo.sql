-- TierS: instalação completa do banco (equivale aos 6 arquivos de migrations em ordem).
-- Cole tudo no SQL Editor do Supabase e clique em Run.
create extension if not exists pgcrypto;

do $$ begin
  create type public.room_status as enum ('lobby','deal','write','place','adjust','reveal','final');
exception when duplicate_object then null; end $$;

create table if not exists public.themes (
  id serial primary key,
  name text not null unique
);

create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  host_user uuid not null,
  status public.room_status not null default 'lobby',
  round int not null default 0,
  theme_id int references public.themes(id),
  last_theme_id int,
  turn_order uuid[] not null default '{}',
  turn int not null default 0,
  revealed int not null default 0,
  round_scored boolean not null default false,
  rounds_done int not null default 0,
  gabaritos int not null default 0,
  version bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.room_codes (
  room_id uuid primary key references public.rooms(id) on delete cascade,
  code text not null unique
);

create table if not exists public.players (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null,
  name text not null check (char_length(name) between 1 and 16),
  color text not null,
  seat int not null check (seat between 0 and 9),
  score int not null default 0,
  hits int not null default 0,
  misses int not null default 0,
  last_delta int,
  last_bad_place int not null default 0,
  last_bad_move int not null default 0,
  joined_at timestamptz not null default now(),
  unique (room_id, user_id),
  unique (room_id, seat)
);

create table if not exists public.cards (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  round int not null,
  author_id uuid not null references public.players(id) on delete cascade,
  answer text check (char_length(answer) between 1 and 40),
  placed_tier int check (placed_tier between 0 and 4),
  placed_init int,
  placed_by uuid references public.players(id) on delete set null,
  placed_seq int,
  last_by uuid references public.players(id) on delete set null,
  last_verb text,
  revealed_tier int,
  unique (room_id, round, author_id)
);

create table if not exists public.card_secrets (
  card_id uuid primary key references public.cards(id) on delete cascade,
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null,
  tier int not null check (tier between 0 and 4)
);

create table if not exists public.moves (
  id bigserial primary key,
  room_id uuid not null references public.rooms(id) on delete cascade,
  round int not null,
  by_player uuid not null references public.players(id) on delete cascade,
  card_id uuid not null references public.cards(id) on delete cascade,
  from_tier int not null,
  to_tier int not null,
  created_at timestamptz not null default now()
);

create table if not exists public.events (
  id bigserial primary key,
  room_id uuid not null references public.rooms(id) on delete cascade,
  text text not null,
  created_at timestamptz not null default now()
);

create index if not exists players_room_idx on public.players(room_id);
create index if not exists cards_room_round_idx on public.cards(room_id, round);
create index if not exists moves_room_round_idx on public.moves(room_id, round);
create index if not exists events_room_idx on public.events(room_id, id desc);

create or replace function public.is_member(p_room uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from players where room_id = p_room and user_id = auth.uid());
$$;

alter table public.themes enable row level security;
alter table public.rooms enable row level security;
alter table public.room_codes enable row level security;
alter table public.players enable row level security;
alter table public.cards enable row level security;
alter table public.card_secrets enable row level security;
alter table public.moves enable row level security;
alter table public.events enable row level security;

drop policy if exists themes_read on public.themes;
create policy themes_read on public.themes for select to authenticated using (true);
drop policy if exists rooms_read on public.rooms;
create policy rooms_read on public.rooms for select to authenticated using (public.is_member(id));
drop policy if exists codes_read on public.room_codes;
create policy codes_read on public.room_codes for select to authenticated
  using (exists (select 1 from public.rooms r where r.id = room_id and r.host_user = auth.uid()));
drop policy if exists players_read on public.players;
create policy players_read on public.players for select to authenticated using (public.is_member(room_id));
drop policy if exists cards_read on public.cards;
create policy cards_read on public.cards for select to authenticated using (public.is_member(room_id));
drop policy if exists secrets_read on public.card_secrets;
create policy secrets_read on public.card_secrets for select to authenticated using (user_id = auth.uid());
drop policy if exists moves_read on public.moves;
create policy moves_read on public.moves for select to authenticated using (public.is_member(room_id));
drop policy if exists events_read on public.events;
create policy events_read on public.events for select to authenticated using (public.is_member(room_id));

create or replace function public._uid() returns uuid language plpgsql stable as $$
begin
  if auth.uid() is null then raise exception 'Faça login para jogar'; end if;
  return auth.uid();
end $$;

create or replace function public._lock_room(p_room uuid) returns public.rooms
language plpgsql security definer set search_path = public as $$
declare r rooms;
begin
  select * into r from rooms where id = p_room for update;
  if not found then raise exception 'Sala não encontrada'; end if;
  return r;
end $$;

create or replace function public._me(p_room uuid) returns public.players
language plpgsql security definer set search_path = public as $$
declare p players;
begin
  select * into p from players where room_id = p_room and user_id = public._uid();
  if not found then raise exception 'Você não está nesta sala'; end if;
  return p;
end $$;

create or replace function public._require_host(r public.rooms) returns void language plpgsql as $$
begin
  if r.host_user <> public._uid() then raise exception 'Só o host pode fazer isso'; end if;
end $$;

create or replace function public._log(p_room uuid, p_text text) returns void
language sql security definer set search_path = public as $$
  insert into events(room_id, text) values (p_room, p_text);
$$;

create or replace function public._bump(p_room uuid) returns void
language sql security definer set search_path = public as $$
  update rooms set version = version + 1, updated_at = now() where id = p_room;
$$;

create or replace function public._tier_letter(t int) returns text language sql immutable as $$
  select (array['S','A','B','C','F'])[t + 1];
$$;

create or replace function public._clean_name(p_name text) returns text language plpgsql immutable as $$
declare v text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
begin
  if char_length(v) < 1 then raise exception 'Digite um apelido'; end if;
  return left(v, 16);
end $$;

create or replace function public._advance_place(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  r rooms;
  n int;
  t int;
  pid uuid;
  i int;
begin
  select * into r from rooms where id = p_room;
  n := array_length(r.turn_order, 1);
  if not exists (select 1 from cards where room_id = p_room and round = r.round and placed_tier is null) then
    update rooms set status = 'adjust', turn = 0 where id = p_room;
    perform _log(p_room, 'Quadro completo! Hora dos ajustes.');
    return;
  end if;
  t := r.turn;
  for i in 1..n loop
    t := t + 1;
    pid := r.turn_order[(t % n) + 1];
    exit when exists (select 1 from cards where room_id = p_room and round = r.round and placed_tier is null and author_id <> pid);
  end loop;
  update rooms set turn = t where id = p_room;
end $$;

create or replace function public._score_round(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  r rooms;
  v_all boolean;
begin
  select * into r from rooms where id = p_room;
  select not exists (
    select 1 from cards c join card_secrets s on s.card_id = c.id
    where c.room_id = p_room and c.round = r.round and c.placed_tier is distinct from s.tier
  ) into v_all;

  with c as (
    select c.id, c.placed_init, c.placed_by, s.tier
    from cards c join card_secrets s on s.card_id = c.id
    where c.room_id = p_room and c.round = r.round
  ), pl as (
    select p.id,
      (select count(*) from c where c.placed_by = p.id and c.placed_init = c.tier)::int as gp,
      (select count(*) from c where c.placed_by = p.id and c.placed_init <> c.tier)::int as bp,
      (select count(*) from moves m join c on c.id = m.card_id
        where m.room_id = p_room and m.round = r.round and m.by_player = p.id
          and abs(m.to_tier - c.tier) < abs(m.from_tier - c.tier))::int as gm,
      (select count(*) from moves m join c on c.id = m.card_id
        where m.room_id = p_room and m.round = r.round and m.by_player = p.id
          and abs(m.to_tier - c.tier) > abs(m.from_tier - c.tier))::int as bm
    from players p where p.room_id = p_room
  )
  update players p set
    last_delta = pl.gp - pl.bp + pl.gm - pl.bm + case when v_all then 2 else 0 end,
    score = p.score + pl.gp - pl.bp + pl.gm - pl.bm + case when v_all then 2 else 0 end,
    hits = p.hits + pl.gp + pl.gm,
    misses = p.misses + pl.bp + pl.bm,
    last_bad_place = pl.bp,
    last_bad_move = pl.bm
  from pl where pl.id = p.id;

  update rooms set round_scored = true, rounds_done = rounds_done + 1,
    gabaritos = gabaritos + case when v_all then 1 else 0 end
  where id = p_room;

  perform _log(p_room, case when v_all then 'GABARITARAM! +2 pra todo mundo' else 'Rodada ' || r.round || ' encerrada' end);
end $$;

create or replace function public.leave_room(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  r rooms := _lock_room(p_room);
  me players := _me(p_room);
  v_next players;
begin
  if r.status <> 'lobby' and r.status <> 'final' then
    raise exception 'Dá pra sair só na sala de espera ou no fim da partida.';
  end if;
  delete from players where id = me.id;
  if r.host_user = me.user_id then
    select * into v_next from players where room_id = p_room order by seat limit 1;
    if not found then
      delete from rooms where id = p_room;
      return;
    end if;
    update rooms set host_user = v_next.user_id where id = p_room;
    perform _log(p_room, v_next.name || ' agora é o host');
  end if;
  perform _log(p_room, me.name || ' saiu da sala');
  perform _bump(p_room);
end $$;



create or replace function public.adjust_pass(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  r rooms := _lock_room(p_room);
  me players := _me(p_room);
begin
  if r.status <> 'adjust' then raise exception 'Agora não é hora de ajustar'; end if;
  if _current_player(r) is distinct from me.id then raise exception 'Não é a sua vez'; end if;
  perform _log(p_room, me.name || ' passou a vez');
  perform _advance_adjust(p_room);
  perform _bump(p_room);
end $$;

create or replace function public.skip_turn(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  r rooms := _lock_room(p_room);
  v_name text;
begin
  perform _require_host(r);
  select name into v_name from players where id = _current_player(r);
  if r.status = 'place' then
    perform _log(p_room, 'O host pulou a vez de ' || coalesce(v_name, '?'));
    perform _advance_place(p_room);
  elsif r.status = 'adjust' then
    perform _log(p_room, 'O host pulou a vez de ' || coalesce(v_name, '?'));
    perform _advance_adjust(p_room);
  else
    raise exception 'Não há vez para pular agora';
  end if;
  perform _bump(p_room);
end $$;

create or replace function public.reveal_next(p_room uuid, p_all boolean default false) returns void
language plpgsql security definer set search_path = public as $$
declare
  r rooms := _lock_room(p_room);
  n int;
  k int;
begin
  perform _require_host(r);
  if r.status <> 'reveal' or r.round_scored then raise exception 'Nada para revelar agora'; end if;
  select count(*) into n from cards where room_id = p_room and round = r.round;
  k := case when p_all then n else least(n, r.revealed + 1) end;
  update cards c set revealed_tier = s.tier
  from card_secrets s
  where s.card_id = c.id and c.id in (
    select id from cards where room_id = p_room and round = r.round
    order by placed_tier, placed_seq limit k
  );
  update rooms set revealed = k where id = p_room;
  if k >= n then perform _score_round(p_room); end if;
  perform _bump(p_room);
end $$;

create or replace function public.end_match(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r rooms := _lock_room(p_room);
begin
  perform _require_host(r);
  if r.status in ('lobby', 'final') then raise exception 'Não há partida em andamento'; end if;
  update rooms set status = 'final' where id = p_room;
  perform _log(p_room, 'O host encerrou a partida');
  perform _bump(p_room);
end $$;

do $$ begin
  alter publication supabase_realtime add table public.rooms;
exception when duplicate_object then null; when undefined_object then null; end $$;

insert into public.themes(name) values
  ('Filmes de comédia'), ('Sabores de pizza'), ('Coisas pra fazer no domingo'), ('Lanches de madrugada'),
  ('Doces brasileiros'), ('Super-heróis'), ('Desenhos da infância'), ('Músicas pra cantar no karaokê'),
  ('Matérias da escola'), ('Comidas de festa junina'), ('Esportes'), ('Animais de estimação'),
  ('Séries de TV'), ('Lugares pra viajar no Brasil'), ('Bebidas'), ('Jogos de tabuleiro'),
  ('Frutas'), ('Feriados'), ('Redes sociais'), ('Vilões de filme'), ('Coisas pra levar na praia'),
  ('Presentes de amigo secreto'), ('Desculpas pra faltar aula'), ('Sobremesas'), ('Sabores de sorvete'),
  ('Filmes de terror'), ('Videogames'), ('Tipos de pão'), ('Comidas de churrasco'), ('Salgados de festa'),
  ('Filmes de animação'), ('Profissões'), ('Superpoderes'), ('Coisas que dão preguiça'), ('Cafés da manhã')
on conflict (name) do nothing;

alter table public.players add column if not exists rerolls int not null default 3;
alter table public.rooms add column if not exists chooser uuid references public.players(id) on delete set null;
alter table public.rooms add column if not exists theme_options int[] not null default '{}';

create or replace function public._theme_options(p_avoid int[]) returns int[]
language sql volatile security definer set search_path = public as $$
  select coalesce(
    (select array_agg(id) from (select id from themes where not (id = any(coalesce(p_avoid, '{}'))) order by random() limit 2) a),
    '{}'
  );
$$;

create or replace function public.choose_theme(p_room uuid, p_theme int) returns void
language plpgsql security definer set search_path = public as $$
declare
  r rooms := _lock_room(p_room);
  me players := _me(p_room);
  v_name text;
begin
  if r.status <> 'deal' then raise exception 'Agora não é hora de escolher o tema'; end if;
  if r.chooser is distinct from me.id then raise exception 'Não é você quem escolhe o tema desta rodada'; end if;
  if not (p_theme = any(r.theme_options)) then raise exception 'Escolha uma das duas opções'; end if;
  select name into v_name from themes where id = p_theme;
  update rooms set theme_id = p_theme, last_theme_id = p_theme, theme_options = '{}', status = 'write' where id = p_room;
  perform _log(p_room, me.name || ' escolheu o tema: ' || v_name);
  perform _bump(p_room);
end $$;

create or replace function public.reassign_chooser(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  r rooms := _lock_room(p_room);
  v_new players;
begin
  perform _require_host(r);
  if r.status <> 'deal' then raise exception 'Agora não é hora de escolher o tema'; end if;
  select * into v_new from players where room_id = p_room and id is distinct from r.chooser order by random() limit 1;
  if not found then raise exception 'Não há outro jogador para escolher'; end if;
  update rooms set chooser = v_new.id where id = p_room;
  perform _log(p_room, 'Agora quem escolhe o tema é ' || v_new.name);
  perform _bump(p_room);
end $$;

create or replace function public.next_round(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r rooms := _lock_room(p_room);
begin
  perform _require_host(r);
  if r.status <> 'reveal' or not r.round_scored then raise exception 'Termine de revelar a rodada primeiro'; end if;
  perform _deal_round(p_room);
  perform _bump(p_room);
end $$;

alter table public.players add column if not exists zeroed_round int;

create or replace function public.reroll_themes(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  r rooms := _lock_room(p_room);
  me players := _me(p_room);
  v_options int[];
begin
  if r.status <> 'deal' then raise exception 'Agora não é hora de escolher o tema'; end if;
  if r.chooser is distinct from me.id then raise exception 'Não é você quem escolhe o tema desta rodada'; end if;
  if me.rerolls <= 0 then raise exception 'Você não tem mais "Sortear novamente". Escolha uma das duas opções.'; end if;
  v_options := _theme_options(r.theme_options || coalesce(r.last_theme_id, -1));
  if coalesce(array_length(v_options, 1), 0) < 2 then
    v_options := _theme_options(array[coalesce(r.last_theme_id, -1)]);
  end if;
  update players set rerolls = rerolls - 1,
    zeroed_round = case when rerolls - 1 = 0 then r.round else null end
  where id = me.id;
  update rooms set theme_options = v_options where id = p_room;
  perform _log(p_room, me.name || ' sorteou novos temas');
  perform _bump(p_room);
end $$;

create or replace function public.new_match(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r rooms := _lock_room(p_room);
begin
  perform _require_host(r);
  if r.status <> 'final' then raise exception 'Encerre a partida primeiro'; end if;
  update players set score = 0, hits = 0, misses = 0, rerolls = 3, zeroed_round = null, last_delta = null, last_bad_place = 0, last_bad_move = 0
    where room_id = p_room;
  update rooms set status = 'lobby', theme_id = null, turn_order = '{}', turn = 0, revealed = 0,
    round_scored = false, rounds_done = 0, gabaritos = 0, chooser = null, theme_options = '{}' where id = p_room;
  perform _log(p_room, 'Nova partida! Esperando a galera');
  perform _bump(p_room);
end $$;

alter table public.rooms add column if not exists max_players int not null default 10 check (max_players between 2 and 10);
alter table public.rooms add column if not exists tiers int[] not null default '{0,1,2,3,4}';
alter table public.rooms add column if not exists tier_cap int not null default 2;
alter table public.rooms add column if not exists adjust_laps int not null default 1;

alter table public.cards drop constraint if exists cards_room_id_round_author_id_key;
alter table public.cards add column if not exists slot int not null default 1;
create unique index if not exists cards_author_slot_idx on public.cards(room_id, round, author_id, slot);

create or replace function public._formation(n int, out tiers int[], out cap int)
language sql immutable as $$
  select case
           when n in (3, 6) then array[0, 2, 4]
           when n in (4, 7, 8) then array[0, 1, 2, 4]
           else array[0, 1, 2, 3, 4]
         end,
         case n when 3 then 3 when 6 then 4 else 2 end;
$$;

create or replace function public._current_player(r public.rooms) returns uuid language plpgsql immutable as $$
declare n int := coalesce(array_length(r.turn_order, 1), 0);
begin
  if n = 0 then return null; end if;
  if r.status = 'place' then return r.turn_order[(r.turn % n) + 1]; end if;
  if r.status = 'adjust' and r.turn < n * r.adjust_laps then return r.turn_order[(r.turn % n) + 1]; end if;
  return null;
end $$;

create or replace function public._advance_adjust(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r rooms;
begin
  update rooms set turn = turn + 1 where id = p_room returning * into r;
  if r.turn >= array_length(r.turn_order, 1) * r.adjust_laps then
    update rooms set status = 'reveal', revealed = 0 where id = p_room;
    perform _log(p_room, 'Ajustes encerrados. Revelação!');
  end if;
end $$;

create or replace function public._deal_round(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  r rooms;
  v_round int;
  n int;
  v_tiers int[];
  v_cap int;
  v_total int;
  v_base int;
  v_extra int;
  v_pool int[];
  v_mine int[];
  v_card uuid;
  v_chooser uuid;
  v_options int[];
  v_count int;
  v_tier int;
  i int := 1;
  k int := 0;
  j int;
  p record;
begin
  select * into r from rooms where id = p_room;
  update rooms set round = round + 1 where id = p_room returning round into v_round;

  for p in select * from players where room_id = p_room and rerolls = 0 and zeroed_round is not null
                                    and v_round >= zeroed_round + 5 loop
    update players set rerolls = 1, zeroed_round = null where id = p.id;
    perform _log(p_room, p.name || ' ganhou 1 "Sortear novamente" de volta');
  end loop;

  select count(*) into n from players where room_id = p_room;
  select f.tiers, f.cap into v_tiers, v_cap from _formation(n) f;
  v_total := array_length(v_tiers, 1) * v_cap;
  v_base := v_total / n;
  v_extra := v_total % n;
  select array_agg(t order by random()) into v_pool
    from unnest(v_tiers) t cross join generate_series(1, v_cap);

  for p in select * from players where room_id = p_room order by seat loop
    v_count := v_base + case when ((k - v_round + 1) % n + n) % n < v_extra then 1 else 0 end;
    if n = 2 then
      select array_agg(t order by random()) into v_mine from unnest(v_tiers) t;
    end if;
    for j in 1..v_count loop
      if n = 2 then
        v_tier := v_mine[j];
      else
        v_tier := v_pool[i];
        i := i + 1;
      end if;
      insert into cards(room_id, round, author_id, slot) values (p_room, v_round, p.id, j) returning id into v_card;
      insert into card_secrets(card_id, room_id, user_id, tier) values (v_card, p_room, p.user_id, v_tier);
    end loop;
    k := k + 1;
  end loop;

  select id into v_chooser from players
    where room_id = p_room and id is distinct from r.chooser
    order by random() limit 1;
  if v_chooser is null then
    select id into v_chooser from players where room_id = p_room order by random() limit 1;
  end if;
  v_options := _theme_options(array[coalesce(r.last_theme_id, -1)]);

  update rooms set status = 'deal', theme_id = null, turn_order = '{}', turn = 0, revealed = 0, round_scored = false,
    chooser = v_chooser, theme_options = v_options,
    tiers = v_tiers, tier_cap = v_cap, adjust_laps = case when n <= 4 then 2 else 1 end
  where id = p_room;
  update players set last_delta = null, last_bad_place = 0, last_bad_move = 0 where room_id = p_room;
  perform _log(p_room, (select name from players where id = v_chooser) || ' vai escolher o tema da rodada ' || v_round);
end $$;

create or replace function public.create_room(p_name text, p_max int default 10) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := _uid();
  v_name text := _clean_name(p_name);
  v_code text;
  v_room uuid;
  v_alpha text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  i int;
begin
  if p_max is null or p_max < 2 or p_max > 10 then raise exception 'Escolha de 2 a 10 jogadores'; end if;
  loop
    v_code := '';
    for i in 1..4 loop
      v_code := v_code || substr(v_alpha, 1 + floor(random() * length(v_alpha))::int, 1);
    end loop;
    exit when not exists (select 1 from room_codes where code = v_code);
  end loop;
  insert into rooms(host_user, max_players) values (v_uid, p_max) returning id into v_room;
  insert into room_codes(room_id, code) values (v_room, v_code);
  insert into players(room_id, user_id, name, color, seat) values (v_room, v_uid, v_name, '#FFD93D', 0);
  perform _log(v_room, v_name || ' criou uma sala para ' || p_max || ' jogadores');
  return v_room;
end $$;

create or replace function public.set_max_players(p_room uuid, p_max int) returns void
language plpgsql security definer set search_path = public as $$
declare
  r rooms := _lock_room(p_room);
  n int;
begin
  perform _require_host(r);
  if r.status <> 'lobby' then raise exception 'Só dá pra mudar o tamanho da sala antes de começar'; end if;
  select count(*) into n from players where room_id = p_room;
  if p_max is null or p_max < 2 or p_max > 10 then raise exception 'Escolha de 2 a 10 jogadores'; end if;
  if p_max < n then raise exception 'Já tem % pessoas na sala', n; end if;
  update rooms set max_players = p_max where id = p_room;
  perform _log(p_room, 'Sala agora é para ' || p_max || ' jogadores');
  perform _bump(p_room);
end $$;

create or replace function public.join_room(p_code text, p_name text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := _uid();
  v_name text := _clean_name(p_name);
  v_room uuid;
  r rooms;
  v_seat int;
  v_colors text[] := array['#FFD93D','#FF6B6B','#FFA94D','#6BCB77','#4CC9F0','#9D8CFF','#F78FB3','#3DDCC4','#F4A261','#FFFFFF'];
begin
  select room_id into v_room from room_codes where code = upper(btrim(p_code));
  if v_room is null then raise exception 'Sala não encontrada. Confira o código.'; end if;
  r := _lock_room(v_room);
  if exists (select 1 from players where room_id = v_room and user_id = v_uid) then
    return v_room;
  end if;
  if r.status <> 'lobby' then raise exception 'Essa partida já começou. Peça pro host abrir uma nova.'; end if;
  if (select count(*) from players where room_id = v_room) >= r.max_players then
    raise exception 'A sala está cheia (% jogadores).', r.max_players;
  end if;
  if exists (select 1 from players where room_id = v_room and lower(name) = lower(v_name)) then
    raise exception 'Já tem alguém com esse apelido na sala.';
  end if;
  select min(s) into v_seat from generate_series(0, 9) s
    where not exists (select 1 from players where room_id = v_room and seat = s);
  insert into players(room_id, user_id, name, color, seat) values (v_room, v_uid, v_name, v_colors[v_seat + 1], v_seat);
  perform _log(v_room, v_name || ' entrou na sala');
  perform _bump(v_room);
  return v_room;
end $$;

create or replace function public.start_game(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  r rooms := _lock_room(p_room);
  n int;
begin
  perform _require_host(r);
  if r.status <> 'lobby' then raise exception 'A partida já começou'; end if;
  select count(*) into n from players where room_id = p_room;
  if n < 2 then raise exception 'Precisa de pelo menos 2 jogadores.'; end if;
  if n < r.max_players then raise exception 'Esperando a sala completar (% de %)', n, r.max_players; end if;
  update players set score = 0, hits = 0, misses = 0, rerolls = 3, zeroed_round = null where room_id = p_room;
  update rooms set round = 0, rounds_done = 0, gabaritos = 0, last_theme_id = null, chooser = null where id = p_room;
  perform _deal_round(p_room);
  perform _log(p_room, 'A partida começou!');
  perform _bump(p_room);
end $$;

create or replace function public.submit_answers(p_room uuid, p_texts text[]) returns void
language plpgsql security definer set search_path = public as $$
declare
  r rooms := _lock_room(p_room);
  me players := _me(p_room);
  c record;
  v text;
  i int := 0;
begin
  if r.status <> 'write' then raise exception 'Agora não é hora de responder'; end if;
  for c in select id from cards where room_id = p_room and round = r.round and author_id = me.id order by slot loop
    i := i + 1;
    v := btrim(regexp_replace(coalesce(p_texts[i], ''), '\s+', ' ', 'g'));
    if char_length(v) < 1 then raise exception 'Preencha todas as suas respostas'; end if;
    update cards set answer = left(v, 40) where id = c.id;
  end loop;
  if not exists (select 1 from cards where room_id = p_room and round = r.round and answer is null) then
    update rooms set status = 'place', turn = 0,
      turn_order = (select array_agg(id order by random()) from players where room_id = p_room)
    where id = p_room;
    perform _log(p_room, 'Todos responderam. Começa o posicionamento!');
  end if;
  perform _bump(p_room);
end $$;

create or replace function public.place_card(p_room uuid, p_card uuid, p_tier int) returns void
language plpgsql security definer set search_path = public as $$
declare
  r rooms := _lock_room(p_room);
  me players := _me(p_room);
  c cards;
  v_seq int;
begin
  if r.status <> 'place' then raise exception 'Agora não é hora de posicionar'; end if;
  if _current_player(r) is distinct from me.id then raise exception 'Não é a sua vez'; end if;
  if p_tier is null or not (p_tier = any(r.tiers)) then raise exception 'Esse Tier não está no quadro'; end if;
  select * into c from cards where id = p_card and room_id = p_room and round = r.round for update;
  if not found then raise exception 'Resposta não encontrada'; end if;
  if c.author_id = me.id then raise exception 'Você não pode posicionar a sua própria resposta'; end if;
  if c.placed_tier is not null then raise exception 'Essa resposta já está no quadro'; end if;
  if (select count(*) from cards where room_id = p_room and round = r.round and placed_tier = p_tier) >= r.tier_cap then
    raise exception 'O Tier % já está cheio', _tier_letter(p_tier);
  end if;
  select coalesce(max(placed_seq), 0) + 1 into v_seq from cards where room_id = p_room and round = r.round;
  update cards set placed_tier = p_tier, placed_init = p_tier, placed_by = me.id, placed_seq = v_seq,
    last_by = me.id, last_verb = 'colocado'
  where id = c.id;
  perform _log(p_room, me.name || ' colocou “' || c.answer || '” no Tier ' || _tier_letter(p_tier));
  perform _advance_place(p_room);
  perform _bump(p_room);
end $$;

create or replace function public.get_state(p_room uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r rooms;
  me players;
  v_is_host boolean;
  v_show_answers boolean;
begin
  select * into r from rooms where id = p_room;
  if not found then raise exception 'Sala não encontrada'; end if;
  me := _me(p_room);
  v_is_host := r.host_user = me.user_id;
  v_show_answers := r.status in ('place', 'adjust', 'reveal');

  return jsonb_build_object(
    'room', jsonb_build_object(
      'id', r.id, 'status', r.status, 'round', r.round,
      'theme', (select name from themes where id = r.theme_id),
      'turn_order', to_jsonb(r.turn_order), 'turn', r.turn, 'revealed', r.revealed,
      'round_scored', r.round_scored, 'rounds_done', r.rounds_done, 'gabaritos', r.gabaritos,
      'version', r.version, 'current_player', _current_player(r),
      'host_player', (select id from players where room_id = p_room and user_id = r.host_user),
      'max_players', r.max_players, 'tiers', to_jsonb(r.tiers), 'tier_cap', r.tier_cap, 'adjust_laps', r.adjust_laps,
      'chooser', r.chooser,
      'theme_options', case when r.chooser = me.id then coalesce((
        select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name) order by array_position(r.theme_options, t.id))
        from themes t where t.id = any(r.theme_options)), '[]'::jsonb) else '[]'::jsonb end
    ),
    'code', case when v_is_host then (select code from room_codes where room_id = p_room) end,
    'is_host', v_is_host,
    'me', me.id,
    'my_cards', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'slot', c.slot, 'tier', s.tier, 'answer', c.answer) order by c.slot)
      from cards c join card_secrets s on s.card_id = c.id
      where c.room_id = p_room and c.round = r.round and c.author_id = me.id), '[]'::jsonb),
    'players', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'name', p.name, 'color', p.color, 'seat', p.seat, 'score', p.score,
        'hits', p.hits, 'misses', p.misses, 'last_delta', p.last_delta,
        'last_bad_place', p.last_bad_place, 'last_bad_move', p.last_bad_move, 'rerolls', p.rerolls,
        'rerolls_back_round', case when p.rerolls = 0 and p.zeroed_round is not null then p.zeroed_round + 5 end,
        'cards', (select count(*) from cards c where c.room_id = p_room and c.round = r.round and c.author_id = p.id),
        'answered', exists (select 1 from cards c where c.room_id = p_room and c.round = r.round and c.author_id = p.id)
          and not exists (select 1 from cards c where c.room_id = p_room and c.round = r.round and c.author_id = p.id and c.answer is null)
      ) order by p.seat) from players p where p.room_id = p_room), '[]'::jsonb),
    'cards', case when r.round = 0 then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'author_id', c.author_id,
        'answer', case when v_show_answers or c.author_id = me.id then c.answer end,
        'placed_tier', c.placed_tier, 'placed_seq', c.placed_seq,
        'last_by', c.last_by, 'last_verb', c.last_verb, 'revealed_tier', c.revealed_tier
      ) order by c.placed_seq nulls last, c.id) from cards c where c.room_id = p_room and c.round = r.round), '[]'::jsonb) end,
    'events', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'text', e.text) order by e.id desc)
      from (select * from events where room_id = p_room order by id desc limit 8) e), '[]'::jsonb)
  );
end $$;



create or replace function public.adjust_move(p_room uuid, p_card uuid, p_dir int, p_swap uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  r rooms := _lock_room(p_room);
  me players := _me(p_room);
  c cards;
  o cards;
  v_from int;
  v_to int;
  v_txt text;
begin
  if r.status <> 'adjust' then raise exception 'Agora não é hora de ajustar'; end if;
  if _current_player(r) is distinct from me.id then raise exception 'Não é a sua vez'; end if;
  if p_dir not in (-1, 1) then raise exception 'Movimento inválido'; end if;
  select * into c from cards where id = p_card and room_id = p_room and round = r.round for update;
  if not found then raise exception 'Resposta não encontrada'; end if;
  if c.author_id = me.id then raise exception 'Você não pode mexer na sua própria resposta'; end if;
  v_from := c.placed_tier;
  v_to := r.tiers[array_position(r.tiers, v_from) + p_dir];
  if v_to is null then raise exception 'Não dá pra mover pra fora do quadro'; end if;

  v_txt := me.name || case when p_dir < 0 then ' subiu “' else ' desceu “' end || c.answer || '” para o Tier ' || _tier_letter(v_to);
  if (select count(*) from cards where room_id = p_room and round = r.round and placed_tier = v_to) >= r.tier_cap then
    if p_swap is null then raise exception 'O Tier % está cheio: escolha com quem trocar', _tier_letter(v_to); end if;
    select * into o from cards where id = p_swap and room_id = p_room and round = r.round and placed_tier = v_to for update;
    if not found then raise exception 'Escolha uma resposta do Tier % para trocar', _tier_letter(v_to); end if;
    if o.author_id = me.id then raise exception 'Você não pode trocar com a sua própria resposta'; end if;
    update cards set placed_tier = v_from, last_by = me.id, last_verb = 'trocado' where id = o.id;
    insert into moves(room_id, round, by_player, card_id, from_tier, to_tier) values (p_room, r.round, me.id, o.id, v_to, v_from);
    v_txt := v_txt || ' (trocou com “' || o.answer || '”)';
  end if;
  update cards set placed_tier = v_to, last_by = me.id, last_verb = 'movido' where id = c.id;
  insert into moves(room_id, round, by_player, card_id, from_tier, to_tier) values (p_room, r.round, me.id, c.id, v_from, v_to);
  perform _log(p_room, v_txt);
  perform _advance_adjust(p_room);
  perform _bump(p_room);
end $$;

insert into public.themes(name) values
  ('Animais selvagens'),
  ('Animais da fazenda'),
  ('Bichos do fundo do mar'),
  ('Insetos'),
  ('Raças de cachorro'),
  ('Raças de gato'),
  ('Aves'),
  ('Dinossauros'),
  ('Pokémons da primeira geração'),
  ('Personagens da Disney'),
  ('Princesas de desenho'),
  ('Vilões de desenho animado'),
  ('Personagens de anime'),
  ('Animes'),
  ('Novelas brasileiras'),
  ('Personagens de novela'),
  ('Reality shows'),
  ('Programas de auditório'),
  ('Apresentadores de TV'),
  ('Séries de comédia'),
  ('Séries de investigação'),
  ('Filmes de ação'),
  ('Filmes de romance'),
  ('Filmes de ficção científica'),
  ('Filmes da Pixar'),
  ('Filmes da Marvel'),
  ('Filmes de Natal'),
  ('Filmes brasileiros'),
  ('Sagas de cinema'),
  ('Filmes que fizeram você chorar'),
  ('Trilhas sonoras de filme'),
  ('Músicas de festa'),
  ('Músicas pra sofrer'),
  ('Hits do verão'),
  ('Gêneros musicais'),
  ('Instrumentos musicais'),
  ('Ritmos brasileiros'),
  ('Músicas de abertura de desenho'),
  ('Músicas infantis'),
  ('Sertanejo'),
  ('Rock nacional'),
  ('Bandas internacionais'),
  ('Jogos de celular'),
  ('Jogos de luta'),
  ('Jogos de corrida'),
  ('Jogos de terror'),
  ('Personagens de videogame'),
  ('Consoles de videogame'),
  ('Jogos de cartas'),
  ('Brincadeiras de criança'),
  ('Brincadeiras de festa'),
  ('Jogos de festa'),
  ('Esportes olímpicos'),
  ('Esportes radicais'),
  ('Posições do futebol'),
  ('Modalidades de luta'),
  ('Exercícios de academia'),
  ('Sabores de suco'),
  ('Refrigerantes'),
  ('Drinks'),
  ('Tipos de café'),
  ('Chás'),
  ('Comidas de rua'),
  ('Comidas de boteco'),
  ('Comidas de vó'),
  ('Pratos típicos brasileiros'),
  ('Comidas japonesas'),
  ('Comidas italianas'),
  ('Comidas mexicanas'),
  ('Fast food'),
  ('Recheios de pastel'),
  ('Sabores de salgadinho'),
  ('Tipos de queijo'),
  ('Molhos'),
  ('Temperos'),
  ('Legumes'),
  ('Verduras'),
  ('Frutas tropicais'),
  ('Sabores de bala'),
  ('Chocolates'),
  ('Biscoitos recheados'),
  ('Sabores de chiclete'),
  ('Acompanhamentos de churrasco'),
  ('Pratos de almoço de domingo'),
  ('Comidas de hospital'),
  ('Comidas de avião'),
  ('Cafés da tarde'),
  ('Comidas de cinema'),
  ('Tipos de batata'),
  ('Tipos de ovo'),
  ('Sanduíches'),
  ('Comidas pra ressaca'),
  ('Cidades brasileiras'),
  ('Praias brasileiras'),
  ('Países pra viajar'),
  ('Lugares pra um primeiro encontro'),
  ('Lugares pra passar as férias'),
  ('Pontos turísticos do mundo'),
  ('Meios de transporte'),
  ('Marcas de carro'),
  ('Carros populares'),
  ('Cores'),
  ('Estações do ano'),
  ('Dias da semana'),
  ('Signos do zodíaco'),
  ('Emojis'),
  ('Gírias'),
  ('Bordões de TV'),
  ('Memes'),
  ('Apps de celular'),
  ('Plataformas de streaming'),
  ('Tipos de influenciador'),
  ('Tipos de professor'),
  ('Tipos de chefe'),
  ('Tipos de colega de trabalho'),
  ('Tipos de amigo'),
  ('Tipos de vizinho'),
  ('Tipos de cliente'),
  ('Tipos de parente na festa de família'),
  ('Matérias da faculdade'),
  ('Cursos de faculdade'),
  ('Profissões que ninguém quer'),
  ('Tarefas domésticas'),
  ('Cômodos da casa'),
  ('Móveis'),
  ('Eletrodomésticos'),
  ('Utensílios de cozinha'),
  ('Objetos de escritório'),
  ('Material escolar'),
  ('Roupas'),
  ('Calçados'),
  ('Acessórios'),
  ('Estilos de roupa'),
  ('Cortes de cabelo'),
  ('Cores de cabelo'),
  ('Cheiros bons'),
  ('Barulhos irritantes'),
  ('Sons da natureza'),
  ('Fenômenos da natureza'),
  ('Desastres de filme'),
  ('Monstros e criaturas'),
  ('Lendas do folclore'),
  ('Datas comemorativas'),
  ('Tradições de Ano Novo'),
  ('Fantasias de Carnaval'),
  ('Fantasias de Halloween'),
  ('Presentes de aniversário'),
  ('Temas de festa infantil'),
  ('Sabores de bolo'),
  ('Desculpas pra chegar atrasado'),
  ('Desculpas pra não sair de casa'),
  ('Coisas que dão medo'),
  ('Coisas que dão nojo'),
  ('Coisas que dão sono'),
  ('Coisas que fazem rir'),
  ('Superstições'),
  ('Hobbies'),
  ('Coisas pra fazer num dia de chuva'),
  ('Coisas pra fazer de madrugada'),
  ('Programas de casal'),
  ('Habilidades inúteis'),
  ('Poderes de vilão'),
  ('Planetas do sistema solar'),
  ('Mascotes de marca'),
  ('Times de futebol brasileiros')
on conflict (name) do nothing;

revoke all on all functions in schema public from public, anon, authenticated;
grant execute on function
  public.create_room(text, int), public.set_max_players(uuid, int), public.join_room(text, text), public.leave_room(uuid),
  public.start_game(uuid), public.choose_theme(uuid, int), public.reroll_themes(uuid), public.reassign_chooser(uuid),
  public.submit_answers(uuid, text[]), public.place_card(uuid, uuid, int), public.adjust_move(uuid, uuid, int, uuid),
  public.adjust_pass(uuid), public.skip_turn(uuid), public.reveal_next(uuid, boolean), public.next_round(uuid),
  public.end_match(uuid), public.new_match(uuid), public.get_state(uuid), public.is_member(uuid)
to authenticated;


-- =====================================================================
-- TierS: contas opcionais
-- Quem quiser cria uma conta (e-mail e senha) com nome, sobrenome, nick e
-- foto. A conta guarda o histórico de partidas e entra no ranking geral.
-- Quem não quiser continua jogando como visitante (login anônimo).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Tabelas
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nick text not null check (char_length(nick) between 2 and 16),
  first_name text not null check (char_length(first_name) between 1 and 40),
  last_name text not null check (char_length(last_name) between 1 and 40),
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists profiles_nick_idx on public.profiles (lower(nick));

-- Resultado de cada partida encerrada pelo host.
create table if not exists public.matches (
  id uuid primary key default gen_random_uuid(),
  room_id uuid,
  host_user uuid not null,
  players_count int not null,
  rounds_done int not null,
  gabaritos int not null,
  ended_at timestamptz not null default now()
);

create table if not exists public.match_players (
  match_id uuid not null references public.matches(id) on delete cascade,
  user_id uuid not null,
  name text not null,
  color text not null,
  position int not null,
  score int not null,
  hits int not null,
  misses int not null,
  primary key (match_id, user_id)
);
create index if not exists match_players_user_idx on public.match_players(user_id, match_id);

alter table public.profiles enable row level security;
alter table public.matches enable row level security;
alter table public.match_players enable row level security;

-- Perfis são públicos para quem está logado (nick e foto aparecem no jogo).
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using (true);
-- matches e match_players: leitura só pelas RPCs abaixo.

-- ---------------------------------------------------------------------
-- Fotos de perfil (Storage): bucket público para leitura, e cada usuário
-- com conta só escreve na própria pasta (<user_id>/...).
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 1048576, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists avatars_read on storage.objects;
create policy avatars_read on storage.objects for select to public using (bucket_id = 'avatars');
drop policy if exists avatars_insert on storage.objects;
create policy avatars_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false);
drop policy if exists avatars_update on storage.objects;
create policy avatars_update on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists avatars_delete on storage.objects;
create policy avatars_delete on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------
-- Ajudantes
-- ---------------------------------------------------------------------
create or replace function public._is_anonymous() returns boolean language sql stable as $$
  select coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false);
$$;

create or replace function public._clean_text(p text, p_min int, p_max int, p_label text) returns text language plpgsql immutable as $$
declare v text := btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g'));
begin
  if char_length(v) < p_min then raise exception 'Preencha %', p_label; end if;
  if char_length(v) > p_max then raise exception '% pode ter no máximo % letras', p_label, p_max; end if;
  return v;
end $$;

-- Nick da conta, se houver; senão o apelido digitado.
create or replace function public._player_name(p_uid uuid, p_name text) returns text
language plpgsql security definer set search_path = public as $$
declare v_nick text;
begin
  select nick into v_nick from profiles where user_id = p_uid;
  if v_nick is not null then return v_nick; end if;
  return _clean_name(p_name);
end $$;

-- ---------------------------------------------------------------------
-- Perfil
-- ---------------------------------------------------------------------
create or replace function public.save_profile(p_nick text, p_first text, p_last text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := _uid();
  v_nick text := _clean_text(p_nick, 2, 16, 'o nick');
  v_first text := _clean_text(p_first, 1, 40, 'o nome');
  v_last text := _clean_text(p_last, 1, 40, 'o sobrenome');
begin
  if _is_anonymous() then raise exception 'Crie uma conta para ter um perfil'; end if;
  if v_nick !~ '^[[:alnum:]_. -]+$' then raise exception 'O nick só pode ter letras, números, espaço, ponto, traço e _'; end if;
  if exists (select 1 from profiles where lower(nick) = lower(v_nick) and user_id <> v_uid) then
    raise exception 'Esse nick já está em uso. Escolha outro.';
  end if;
  insert into profiles(user_id, nick, first_name, last_name) values (v_uid, v_nick, v_first, v_last)
  on conflict (user_id) do update set nick = excluded.nick, first_name = excluded.first_name,
    last_name = excluded.last_name, updated_at = now();
  -- Quem está numa sala de espera já aparece com o nick novo.
  update players p set name = v_nick from rooms r
    where p.room_id = r.id and p.user_id = v_uid and r.status = 'lobby'
      and not exists (select 1 from players o where o.room_id = p.room_id and o.id <> p.id and lower(o.name) = lower(v_nick));
  return get_profile(null);
end $$;

-- Caminho da foto no bucket "avatars" (ou null para remover).
create or replace function public.set_avatar(p_path text) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := _uid();
begin
  if _is_anonymous() then raise exception 'Crie uma conta para ter um perfil'; end if;
  if p_path is not null and p_path !~ ('^' || v_uid::text || '/') then raise exception 'Foto inválida'; end if;
  update profiles set avatar_path = p_path, updated_at = now() where user_id = v_uid;
  if not found then raise exception 'Complete o seu perfil primeiro'; end if;
end $$;

-- Perfil com estatísticas, histórico e posição no ranking. Nome e sobrenome
-- só aparecem para o próprio dono.
create or replace function public.get_profile(p_user uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := _uid();
  v_target uuid := coalesce(p_user, v_me);
  pr profiles;
  v_stats jsonb;
  v_rank int;
begin
  select * into pr from profiles where user_id = v_target;
  if not found then return null; end if;

  select jsonb_build_object(
    'matches', count(*),
    'wins', count(*) filter (where mp.position = 1),
    'points', coalesce(sum(mp.score), 0),
    'hits', coalesce(sum(mp.hits), 0),
    'misses', coalesce(sum(mp.misses), 0),
    'best', coalesce(max(mp.score), 0),
    'gabaritos', coalesce(sum(m.gabaritos), 0)
  ) into v_stats
  from match_players mp join matches m on m.id = mp.match_id
  where mp.user_id = v_target;

  with t as (
    select mp.user_id, count(*) filter (where mp.position = 1) as wins, sum(mp.score) as points, sum(mp.hits) as hits
    from match_players mp join profiles p on p.user_id = mp.user_id
    group by mp.user_id
  ), mine as (select * from t where user_id = v_target)
  select count(*) + 1 into v_rank from t, mine
  where (t.wins, t.points, t.hits) > (mine.wins, mine.points, mine.hits);
  if not exists (select 1 from match_players where user_id = v_target) then v_rank := null; end if;

  return jsonb_build_object(
    'user_id', pr.user_id,
    'nick', pr.nick,
    'first_name', case when v_target = v_me then pr.first_name end,
    'last_name', case when v_target = v_me then pr.last_name end,
    'avatar_path', pr.avatar_path,
    'created_at', pr.created_at,
    'is_me', v_target = v_me,
    'rank', v_rank,
    'stats', v_stats,
    'history', coalesce((select jsonb_agg(jsonb_build_object(
        'id', h.id, 'ended_at', h.ended_at, 'players_count', h.players_count, 'rounds_done', h.rounds_done,
        'gabaritos', h.gabaritos, 'position', h.position, 'score', h.score, 'hits', h.hits, 'misses', h.misses,
        'winner', (select w.name from match_players w where w.match_id = h.id and w.position = 1 limit 1)
      ) order by h.ended_at desc)
      from (select m.id, m.ended_at, m.players_count, m.rounds_done, m.gabaritos, mp.position, mp.score, mp.hits, mp.misses
            from matches m join match_players mp on mp.match_id = m.id
            where mp.user_id = v_target order by m.ended_at desc limit 20) h), '[]'::jsonb)
  );
end $$;

-- Ranking geral entre contas (quem já jogou pelo menos uma partida).
create or replace function public.get_ranking(p_limit int default 50) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me uuid := _uid();
begin
  return coalesce((select jsonb_agg(row_to_json(r)) from (
    select p.user_id, p.nick, p.avatar_path, p.user_id = v_me as is_me,
      count(*)::int as matches,
      (count(*) filter (where mp.position = 1))::int as wins,
      sum(mp.score)::int as points,
      sum(mp.hits)::int as hits,
      sum(mp.misses)::int as misses
    from profiles p join match_players mp on mp.user_id = p.user_id
    group by p.user_id, p.nick, p.avatar_path
    order by wins desc, points desc, hits desc, lower(p.nick)
    limit greatest(1, least(coalesce(p_limit, 50), 200))
  ) r), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------
-- Jogo: nick e foto da conta entram na sala; encerrar grava a partida
-- ---------------------------------------------------------------------
create or replace function public.create_room(p_name text, p_max int default 10) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := _uid();
  v_name text := _player_name(v_uid, p_name);
  v_code text;
  v_room uuid;
  v_alpha text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  i int;
begin
  if p_max is null or p_max < 2 or p_max > 10 then raise exception 'Escolha de 2 a 10 jogadores'; end if;
  loop
    v_code := '';
    for i in 1..4 loop
      v_code := v_code || substr(v_alpha, 1 + floor(random() * length(v_alpha))::int, 1);
    end loop;
    exit when not exists (select 1 from room_codes where code = v_code);
  end loop;
  insert into rooms(host_user, max_players) values (v_uid, p_max) returning id into v_room;
  insert into room_codes(room_id, code) values (v_room, v_code);
  insert into players(room_id, user_id, name, color, seat) values (v_room, v_uid, v_name, '#FFD93D', 0);
  perform _log(v_room, v_name || ' criou uma sala para ' || p_max || ' jogadores');
  return v_room;
end $$;

create or replace function public.join_room(p_code text, p_name text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := _uid();
  v_name text := _player_name(v_uid, p_name);
  v_room uuid;
  r rooms;
  v_seat int;
  v_colors text[] := array['#FFD93D','#FF6B6B','#FFA94D','#6BCB77','#4CC9F0','#9D8CFF','#F78FB3','#3DDCC4','#F4A261','#FFFFFF'];
begin
  select room_id into v_room from room_codes where code = upper(btrim(p_code));
  if v_room is null then raise exception 'Sala não encontrada. Confira o código.'; end if;
  r := _lock_room(v_room);
  if exists (select 1 from players where room_id = v_room and user_id = v_uid) then
    return v_room;
  end if;
  if r.status <> 'lobby' then raise exception 'Essa partida já começou. Peça pro host abrir uma nova.'; end if;
  if (select count(*) from players where room_id = v_room) >= r.max_players then
    raise exception 'A sala está cheia (% jogadores).', r.max_players;
  end if;
  if exists (select 1 from players where room_id = v_room and lower(name) = lower(v_name)) then
    raise exception 'Já tem alguém com esse apelido na sala.';
  end if;
  select min(s) into v_seat from generate_series(0, 9) s
    where not exists (select 1 from players where room_id = v_room and seat = s);
  insert into players(room_id, user_id, name, color, seat) values (v_room, v_uid, v_name, v_colors[v_seat + 1], v_seat);
  perform _log(v_room, v_name || ' entrou na sala');
  perform _bump(v_room);
  return v_room;
end $$;

create or replace function public.end_match(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  r rooms := _lock_room(p_room);
  v_match uuid;
  n int;
begin
  perform _require_host(r);
  if r.status in ('lobby', 'final') then raise exception 'Não há partida em andamento'; end if;
  update rooms set status = 'final' where id = p_room;

  -- Grava o resultado para o histórico e o ranking das contas.
  select count(*) into n from players where room_id = p_room;
  if r.rounds_done > 0 and n > 0 then
    insert into matches(room_id, host_user, players_count, rounds_done, gabaritos)
      values (p_room, r.host_user, n, r.rounds_done, r.gabaritos) returning id into v_match;
    insert into match_players(match_id, user_id, name, color, position, score, hits, misses)
      select v_match, p.user_id, p.name, p.color,
        rank() over (order by p.score desc, p.hits desc, p.misses asc, p.seat asc),
        p.score, p.hits, p.misses
      from players p where p.room_id = p_room;
  end if;

  perform _log(p_room, 'O host encerrou a partida');
  perform _bump(p_room);
end $$;

create or replace function public.get_state(p_room uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r rooms;
  me players;
  v_is_host boolean;
  v_show_answers boolean;
begin
  select * into r from rooms where id = p_room;
  if not found then raise exception 'Sala não encontrada'; end if;
  me := _me(p_room);
  v_is_host := r.host_user = me.user_id;
  v_show_answers := r.status in ('place', 'adjust', 'reveal');

  return jsonb_build_object(
    'room', jsonb_build_object(
      'id', r.id, 'status', r.status, 'round', r.round,
      'theme', (select name from themes where id = r.theme_id),
      'turn_order', to_jsonb(r.turn_order), 'turn', r.turn, 'revealed', r.revealed,
      'round_scored', r.round_scored, 'rounds_done', r.rounds_done, 'gabaritos', r.gabaritos,
      'version', r.version, 'current_player', _current_player(r),
      'host_player', (select id from players where room_id = p_room and user_id = r.host_user),
      'max_players', r.max_players, 'tiers', to_jsonb(r.tiers), 'tier_cap', r.tier_cap, 'adjust_laps', r.adjust_laps,
      'chooser', r.chooser,
      'theme_options', case when r.chooser = me.id then coalesce((
        select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name) order by array_position(r.theme_options, t.id))
        from themes t where t.id = any(r.theme_options)), '[]'::jsonb) else '[]'::jsonb end
    ),
    'code', case when v_is_host then (select code from room_codes where room_id = p_room) end,
    'is_host', v_is_host,
    'me', me.id,
    'my_cards', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'slot', c.slot, 'tier', s.tier, 'answer', c.answer) order by c.slot)
      from cards c join card_secrets s on s.card_id = c.id
      where c.room_id = p_room and c.round = r.round and c.author_id = me.id), '[]'::jsonb),
    'players', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'name', p.name, 'color', p.color, 'seat', p.seat, 'score', p.score,
        'hits', p.hits, 'misses', p.misses, 'last_delta', p.last_delta,
        'last_bad_place', p.last_bad_place, 'last_bad_move', p.last_bad_move, 'rerolls', p.rerolls,
        'rerolls_back_round', case when p.rerolls = 0 and p.zeroed_round is not null then p.zeroed_round + 5 end,
        'cards', (select count(*) from cards c where c.room_id = p_room and c.round = r.round and c.author_id = p.id),
        'answered', exists (select 1 from cards c where c.room_id = p_room and c.round = r.round and c.author_id = p.id)
          and not exists (select 1 from cards c where c.room_id = p_room and c.round = r.round and c.author_id = p.id and c.answer is null),
        'avatar', (select pr.avatar_path from profiles pr where pr.user_id = p.user_id),
        'registered', exists (select 1 from profiles pr where pr.user_id = p.user_id)
      ) order by p.seat) from players p where p.room_id = p_room), '[]'::jsonb),
    'cards', case when r.round = 0 then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'author_id', c.author_id,
        'answer', case when v_show_answers or c.author_id = me.id then c.answer end,
        'placed_tier', c.placed_tier, 'placed_seq', c.placed_seq,
        'last_by', c.last_by, 'last_verb', c.last_verb, 'revealed_tier', c.revealed_tier
      ) order by c.placed_seq nulls last, c.id) from cards c where c.room_id = p_room and c.round = r.round), '[]'::jsonb) end,
    'events', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'text', e.text) order by e.id desc)
      from (select * from events where room_id = p_room order by id desc limit 8) e), '[]'::jsonb)
  );
end $$;

-- ---------------------------------------------------------------------
-- Permissões: só as RPCs do jogo e do perfil ficam expostas.
-- ---------------------------------------------------------------------
revoke all on all functions in schema public from public, anon, authenticated;
grant execute on function
  public.create_room(text, int), public.set_max_players(uuid, int), public.join_room(text, text), public.leave_room(uuid),
  public.start_game(uuid), public.choose_theme(uuid, int), public.reroll_themes(uuid), public.reassign_chooser(uuid),
  public.submit_answers(uuid, text[]), public.place_card(uuid, uuid, int), public.adjust_move(uuid, uuid, int, uuid),
  public.adjust_pass(uuid), public.skip_turn(uuid), public.reveal_next(uuid, boolean), public.next_round(uuid),
  public.end_match(uuid), public.new_match(uuid), public.get_state(uuid), public.is_member(uuid),
  public.save_profile(text, text, text), public.set_avatar(text), public.get_profile(uuid), public.get_ranking(int)
to authenticated;


-- =====================================================================
-- TierS: amigos
-- Cada conta ganha um código de amigo (6 letras, único). Quem digita o
-- código de alguém vira amigo dessa pessoa (nos dois sentidos). O ranking
-- deixa de ser geral e passa a ser entre você e seus amigos.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Código de amigo
-- ---------------------------------------------------------------------
alter table public.profiles add column if not exists friend_code text;
create unique index if not exists profiles_friend_code_idx on public.profiles (friend_code);

-- Mesmo alfabeto do código da sala (sem 0/O e 1/I, que confundem).
create or replace function public._new_friend_code() returns text language plpgsql as $$
declare
  v_alpha text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v text;
  i int;
begin
  loop
    v := '';
    for i in 1..6 loop
      v := v || substr(v_alpha, 1 + floor(random() * length(v_alpha))::int, 1);
    end loop;
    exit when not exists (select 1 from profiles where friend_code = v);
  end loop;
  return v;
end $$;

create or replace function public._fill_friend_code() returns trigger language plpgsql as $$
begin
  if new.friend_code is null then new.friend_code := _new_friend_code(); end if;
  return new;
end $$;

drop trigger if exists profiles_friend_code on public.profiles;
create trigger profiles_friend_code before insert on public.profiles
  for each row execute function public._fill_friend_code();

-- Contas que já existiam ganham o código agora.
update public.profiles set friend_code = public._new_friend_code() where friend_code is null;
alter table public.profiles alter column friend_code set not null;

-- ---------------------------------------------------------------------
-- Amizades (sempre mútuas; guardadas uma vez, com user_a < user_b)
-- ---------------------------------------------------------------------
create table if not exists public.friendships (
  user_a uuid not null references public.profiles(user_id) on delete cascade,
  user_b uuid not null references public.profiles(user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);
create index if not exists friendships_b_idx on public.friendships (user_b);
alter table public.friendships enable row level security;
-- Sem policies: leitura e escrita só pelas RPCs abaixo.

create or replace function public._friends_of(p_uid uuid) returns setof uuid language sql stable as $$
  select user_b from friendships where user_a = p_uid
  union all
  select user_a from friendships where user_b = p_uid;
$$;

-- Lista de amigos, em ordem alfabética.
create or replace function public.get_friends() returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me uuid := _uid();
begin
  return coalesce((select jsonb_agg(jsonb_build_object(
      'user_id', p.user_id, 'nick', p.nick, 'avatar_path', p.avatar_path, 'since', f.created_at
    ) order by lower(p.nick))
    from friendships f
    join profiles p on p.user_id = case when f.user_a = v_me then f.user_b else f.user_a end
    where v_me in (f.user_a, f.user_b)), '[]'::jsonb);
end $$;

-- Adiciona um amigo pelo código dele. Devolve o nick de quem foi adicionado
-- e a lista atualizada.
create or replace function public.add_friend(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := _uid();
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_other profiles;
begin
  if _is_anonymous() then raise exception 'Crie uma conta para adicionar amigos'; end if;
  if not exists (select 1 from profiles where user_id = v_me) then raise exception 'Complete o seu perfil primeiro'; end if;
  if char_length(v_code) <> 6 then raise exception 'O código de amigo tem 6 caracteres'; end if;
  select * into v_other from profiles where friend_code = v_code;
  if not found then raise exception 'Código não encontrado. Confira com seu amigo.'; end if;
  if v_other.user_id = v_me then raise exception 'Esse é o seu próprio código!'; end if;
  if exists (select 1 from friendships where (user_a, user_b) = (least(v_me, v_other.user_id), greatest(v_me, v_other.user_id))) then
    raise exception 'Vocês já são amigos.';
  end if;
  if (select count(*) from _friends_of(v_me)) >= 200 then raise exception 'Você chegou ao limite de 200 amigos'; end if;
  insert into friendships(user_a, user_b) values (least(v_me, v_other.user_id), greatest(v_me, v_other.user_id));
  return jsonb_build_object('added', v_other.nick, 'friends', get_friends());
end $$;

create or replace function public.remove_friend(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me uuid := _uid();
begin
  delete from friendships where (user_a, user_b) = (least(v_me, p_user), greatest(v_me, p_user));
  return get_friends();
end $$;

-- ---------------------------------------------------------------------
-- Ranking entre amigos: você e todos os seus amigos, inclusive quem ainda
-- não jogou. Ordem: vitórias, pontos, acertos, nick.
-- ---------------------------------------------------------------------
create or replace function public.get_ranking(p_limit int default 50) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_me uuid := _uid();
begin
  return coalesce((select jsonb_agg(row_to_json(r)) from (
    select p.user_id, p.nick, p.avatar_path, p.user_id = v_me as is_me,
      count(mp.match_id)::int as matches,
      (count(*) filter (where mp.position = 1))::int as wins,
      coalesce(sum(mp.score), 0)::int as points,
      coalesce(sum(mp.hits), 0)::int as hits,
      coalesce(sum(mp.misses), 0)::int as misses
    from profiles p left join match_players mp on mp.user_id = p.user_id
    where p.user_id = v_me or p.user_id in (select _friends_of(v_me))
    group by p.user_id, p.nick, p.avatar_path
    order by wins desc, points desc, hits desc, lower(p.nick)
    limit greatest(1, least(coalesce(p_limit, 50), 200))
  ) r), '[]'::jsonb);
end $$;

-- Perfil: ganha o código de amigo (só para o dono), a quantidade de amigos
-- e a posição no ranking entre amigos (null para quem ainda não jogou).
create or replace function public.get_profile(p_user uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := _uid();
  v_target uuid := coalesce(p_user, v_me);
  pr profiles;
  v_stats jsonb;
  v_rank int;
begin
  select * into pr from profiles where user_id = v_target;
  if not found then return null; end if;

  select jsonb_build_object(
    'matches', count(*),
    'wins', count(*) filter (where mp.position = 1),
    'points', coalesce(sum(mp.score), 0),
    'hits', coalesce(sum(mp.hits), 0),
    'misses', coalesce(sum(mp.misses), 0),
    'best', coalesce(max(mp.score), 0),
    'gabaritos', coalesce(sum(m.gabaritos), 0)
  ) into v_stats
  from match_players mp join matches m on m.id = mp.match_id
  where mp.user_id = v_target;

  with t as (
    select p.user_id,
      count(*) filter (where mp.position = 1) as wins,
      coalesce(sum(mp.score), 0) as points,
      coalesce(sum(mp.hits), 0) as hits
    from profiles p left join match_players mp on mp.user_id = p.user_id
    where p.user_id = v_target or p.user_id in (select _friends_of(v_target))
    group by p.user_id
  ), mine as (select * from t where user_id = v_target)
  select count(*) + 1 into v_rank from t, mine
  where (t.wins, t.points, t.hits) > (mine.wins, mine.points, mine.hits);
  if not exists (select 1 from match_players where user_id = v_target) then v_rank := null; end if;

  return jsonb_build_object(
    'user_id', pr.user_id,
    'nick', pr.nick,
    'first_name', case when v_target = v_me then pr.first_name end,
    'last_name', case when v_target = v_me then pr.last_name end,
    'friend_code', case when v_target = v_me then pr.friend_code end,
    'friends', (select count(*) from _friends_of(v_target)),
    'avatar_path', pr.avatar_path,
    'created_at', pr.created_at,
    'is_me', v_target = v_me,
    'rank', v_rank,
    'stats', v_stats,
    'history', coalesce((select jsonb_agg(jsonb_build_object(
        'id', h.id, 'ended_at', h.ended_at, 'players_count', h.players_count, 'rounds_done', h.rounds_done,
        'gabaritos', h.gabaritos, 'position', h.position, 'score', h.score, 'hits', h.hits, 'misses', h.misses,
        'winner', (select w.name from match_players w where w.match_id = h.id and w.position = 1 limit 1)
      ) order by h.ended_at desc)
      from (select m.id, m.ended_at, m.players_count, m.rounds_done, m.gabaritos, mp.position, mp.score, mp.hits, mp.misses
            from matches m join match_players mp on mp.match_id = m.id
            where mp.user_id = v_target order by m.ended_at desc limit 20) h), '[]'::jsonb)
  );
end $$;

-- ---------------------------------------------------------------------
-- Permissões
-- ---------------------------------------------------------------------
revoke all on function public._new_friend_code(), public._fill_friend_code(), public._friends_of(uuid) from public, anon, authenticated;
grant execute on function public.get_friends(), public.add_friend(text), public.remove_friend(uuid) to authenticated;
