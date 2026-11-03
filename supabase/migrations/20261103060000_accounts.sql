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
