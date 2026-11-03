-- =====================================================================
-- TierS: schema, segurança (RLS) e regras do jogo
-- Toda mudança de estado passa por funções RPC (security definer).
-- O cliente só lê; o Tier secreto de cada resposta fica em card_secrets,
-- visível apenas para o autor até a revelação.
-- =====================================================================

create extension if not exists pgcrypto;

do $$ begin
  create type public.room_status as enum ('lobby','deal','write','place','adjust','reveal','final');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
-- Tabelas
-- ---------------------------------------------------------------------
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

-- O código fica separado: só o host consegue ler (e compartilhar).
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

-- ---------------------------------------------------------------------
-- Segurança
-- ---------------------------------------------------------------------
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
-- Nenhuma policy de insert/update/delete: escrita só pelas funções abaixo.

-- ---------------------------------------------------------------------
-- Ajudantes internos
-- ---------------------------------------------------------------------
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

-- Distribui os Tiers secretos e abre uma nova rodada.
create or replace function public._deal_round(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_round int;
  v_pool int[];
  v_card uuid;
  i int := 1;
  p record;
begin
  update rooms set round = round + 1 where id = p_room returning round into v_round;
  select array_agg(t order by random()) into v_pool from unnest(array[0,0,1,1,2,2,3,3,4,4]) t;
  for p in select * from players where room_id = p_room order by seat loop
    insert into cards(room_id, round, author_id) values (p_room, v_round, p.id) returning id into v_card;
    insert into card_secrets(card_id, room_id, user_id, tier) values (v_card, p_room, p.user_id, v_pool[i]);
    i := i + 1;
  end loop;
  update rooms set status = 'deal', theme_id = null, turn_order = '{}', turn = 0, revealed = 0, round_scored = false
    where id = p_room;
  update players set last_delta = null, last_bad_place = 0, last_bad_move = 0 where room_id = p_room;
end $$;

create or replace function public._current_player(r public.rooms) returns uuid language plpgsql immutable as $$
declare n int := coalesce(array_length(r.turn_order, 1), 0);
begin
  if n = 0 then return null; end if;
  if r.status = 'place' then return r.turn_order[(r.turn % n) + 1]; end if;
  if r.status = 'adjust' and r.turn < n then return r.turn_order[r.turn + 1]; end if;
  return null;
end $$;

-- Passa a vez no posicionamento, pulando quem só tem a própria resposta sobrando.
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

create or replace function public._advance_adjust(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r rooms;
begin
  update rooms set turn = turn + 1 where id = p_room returning * into r;
  if r.turn >= array_length(r.turn_order, 1) then
    update rooms set status = 'reveal', revealed = 0 where id = p_room;
    perform _log(p_room, 'Ajustes encerrados. Revelação!');
  end if;
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

-- ---------------------------------------------------------------------
-- RPCs públicas
-- ---------------------------------------------------------------------
create or replace function public.create_room(p_name text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := _uid();
  v_name text := _clean_name(p_name);
  v_code text;
  v_room uuid;
  v_alpha text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  i int;
begin
  loop
    v_code := '';
    for i in 1..4 loop
      v_code := v_code || substr(v_alpha, 1 + floor(random() * length(v_alpha))::int, 1);
    end loop;
    exit when not exists (select 1 from room_codes where code = v_code);
  end loop;
  insert into rooms(host_user) values (v_uid) returning id into v_room;
  insert into room_codes(room_id, code) values (v_room, v_code);
  insert into players(room_id, user_id, name, color, seat) values (v_room, v_uid, v_name, '#FFD93D', 0);
  perform _log(v_room, v_name || ' criou a sala');
  return v_room;
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
  if (select count(*) from players where room_id = v_room) >= 10 then raise exception 'A sala está cheia (10 jogadores).'; end if;
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

create or replace function public.start_game(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  r rooms := _lock_room(p_room);
  n int;
begin
  perform _require_host(r);
  if r.status <> 'lobby' then raise exception 'A partida já começou'; end if;
  select count(*) into n from players where room_id = p_room;
  if n < 3 then raise exception 'Precisa de pelo menos 3 jogadores.'; end if;
  update players set score = 0, hits = 0, misses = 0 where room_id = p_room;
  update rooms set round = 0, rounds_done = 0, gabaritos = 0, last_theme_id = null where id = p_room;
  perform _deal_round(p_room);
  perform _log(p_room, 'A partida começou!');
  perform _bump(p_room);
end $$;

create or replace function public.spin_theme(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  r rooms := _lock_room(p_room);
  v_theme themes;
begin
  perform _require_host(r);
  if r.status <> 'deal' then raise exception 'Agora não é hora de sortear o tema'; end if;
  select * into v_theme from themes where id is distinct from r.last_theme_id order by random() limit 1;
  if not found then raise exception 'Nenhum tema cadastrado'; end if;
  update rooms set theme_id = v_theme.id, last_theme_id = v_theme.id, status = 'write' where id = p_room;
  perform _log(p_room, 'Tema da rodada ' || r.round || ': ' || v_theme.name);
  perform _bump(p_room);
end $$;

create or replace function public.submit_answer(p_room uuid, p_text text) returns void
language plpgsql security definer set search_path = public as $$
declare
  r rooms := _lock_room(p_room);
  me players := _me(p_room);
  v_text text := btrim(regexp_replace(coalesce(p_text, ''), '\s+', ' ', 'g'));
begin
  if r.status <> 'write' then raise exception 'Agora não é hora de responder'; end if;
  if char_length(v_text) < 1 then raise exception 'Escreva uma resposta'; end if;
  update cards set answer = left(v_text, 40) where room_id = p_room and round = r.round and author_id = me.id;
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
  if p_tier is null or p_tier < 0 or p_tier > 4 then raise exception 'Tier inválido'; end if;
  select * into c from cards where id = p_card and room_id = p_room and round = r.round for update;
  if not found then raise exception 'Resposta não encontrada'; end if;
  if c.author_id = me.id then raise exception 'Você não pode posicionar a sua própria resposta'; end if;
  if c.placed_tier is not null then raise exception 'Essa resposta já está no quadro'; end if;
  if (select count(*) from cards where room_id = p_room and round = r.round and placed_tier = p_tier) >= 2 then
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
  v_to := v_from + p_dir;
  if v_to < 0 or v_to > 4 then raise exception 'Não dá pra mover pra fora do quadro'; end if;

  v_txt := me.name || case when p_dir < 0 then ' subiu “' else ' desceu “' end || c.answer || '” para o Tier ' || _tier_letter(v_to);
  if (select count(*) from cards where room_id = p_room and round = r.round and placed_tier = v_to) >= 2 then
    if p_swap is null then raise exception 'O Tier % está cheio: escolha com quem trocar', _tier_letter(v_to); end if;
    select * into o from cards where id = p_swap and room_id = p_room and round = r.round and placed_tier = v_to for update;
    if not found then raise exception 'Escolha uma resposta do Tier % para trocar', _tier_letter(v_to); end if;
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

-- O host pode pular a vez de quem sumiu (caiu a internet, foi pegar pizza...).
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

create or replace function public.next_round(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r rooms := _lock_room(p_room);
begin
  perform _require_host(r);
  if r.status <> 'reveal' or not r.round_scored then raise exception 'Termine de revelar a rodada primeiro'; end if;
  perform _deal_round(p_room);
  perform _log(p_room, 'Rodada ' || (r.round + 1) || '! Sorteando um novo tema...');
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

create or replace function public.new_match(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r rooms := _lock_room(p_room);
begin
  perform _require_host(r);
  if r.status <> 'final' then raise exception 'Encerre a partida primeiro'; end if;
  update players set score = 0, hits = 0, misses = 0, last_delta = null, last_bad_place = 0, last_bad_move = 0 where room_id = p_room;
  update rooms set status = 'lobby', round = round, theme_id = null, turn_order = '{}', turn = 0, revealed = 0,
    round_scored = false, rounds_done = 0, gabaritos = 0 where id = p_room;
  perform _log(p_room, 'Nova partida! Esperando a galera');
  perform _bump(p_room);
end $$;

-- Tudo que a tela precisa, num pedido só (e sem vazar segredos).
create or replace function public.get_state(p_room uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r rooms;
  me players;
  v_is_host boolean;
  v_my_card cards;
  v_my_tier int;
  v_show_answers boolean;
begin
  select * into r from rooms where id = p_room;
  if not found then raise exception 'Sala não encontrada'; end if;
  me := _me(p_room);
  v_is_host := r.host_user = me.user_id;
  v_show_answers := r.status in ('place', 'adjust', 'reveal');
  select * into v_my_card from cards where room_id = p_room and round = r.round and author_id = me.id;
  select tier into v_my_tier from card_secrets where card_id = v_my_card.id;

  return jsonb_build_object(
    'room', jsonb_build_object(
      'id', r.id, 'status', r.status, 'round', r.round,
      'theme', (select name from themes where id = r.theme_id),
      'turn_order', to_jsonb(r.turn_order), 'turn', r.turn, 'revealed', r.revealed,
      'round_scored', r.round_scored, 'rounds_done', r.rounds_done, 'gabaritos', r.gabaritos,
      'version', r.version, 'current_player', _current_player(r),
      'host_player', (select id from players where room_id = p_room and user_id = r.host_user)
    ),
    'code', case when v_is_host then (select code from room_codes where room_id = p_room) end,
    'is_host', v_is_host,
    'me', me.id,
    'my_card', v_my_card.id,
    'my_tier', v_my_tier,
    'my_answer', v_my_card.answer,
    'players', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'name', p.name, 'color', p.color, 'seat', p.seat, 'score', p.score,
        'hits', p.hits, 'misses', p.misses, 'last_delta', p.last_delta,
        'last_bad_place', p.last_bad_place, 'last_bad_move', p.last_bad_move,
        'answered', exists (select 1 from cards c where c.room_id = p_room and c.round = r.round and c.author_id = p.id and c.answer is not null)
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
-- Permissões das funções
-- ---------------------------------------------------------------------
revoke all on all functions in schema public from public, anon, authenticated;
grant execute on function
  public.create_room(text), public.join_room(text, text), public.leave_room(uuid),
  public.start_game(uuid), public.spin_theme(uuid), public.submit_answer(uuid, text),
  public.place_card(uuid, uuid, int), public.adjust_move(uuid, uuid, int, uuid), public.adjust_pass(uuid),
  public.skip_turn(uuid), public.reveal_next(uuid, boolean), public.next_round(uuid),
  public.end_match(uuid), public.new_match(uuid), public.get_state(uuid), public.is_member(uuid)
to authenticated;

-- ---------------------------------------------------------------------
-- Realtime: os clientes escutam só a linha da sala (o campo version muda
-- a cada jogada) e então buscam o estado com get_state.
-- ---------------------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.rooms;
exception when duplicate_object then null; when undefined_object then null; end $$;

-- ---------------------------------------------------------------------
-- Temas
-- ---------------------------------------------------------------------
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
