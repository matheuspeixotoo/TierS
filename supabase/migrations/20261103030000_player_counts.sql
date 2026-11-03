-- =====================================================================
-- TierS: formações por número de jogadores (2 a 10)
-- O host escolhe o tamanho da sala. A partida só começa com a sala completa.
--
--  Jogadores | Tiers      | Respostas por Tier | Respostas por jogador
--  2         | S A B C F  | 2                  | 5 (um de cada Tier)
--  3         | S B F      | 3                  | 3
--  4         | S A B F    | 2                  | 2
--  5         | S A B C F  | 2                  | 2
--  6         | S B F      | 4                  | 2
--  7         | S A B F    | 2                  | 1 (um jogador escreve 2, revezando)
--  8         | S A B F    | 2                  | 1
--  9         | S A B C F  | 2                  | 1 (um jogador escreve 2, revezando)
--  10        | S A B C F  | 2                  | 1
--
-- Com até 4 jogadores, os ajustes têm 2 voltas (cada um ajusta 2 vezes).
-- =====================================================================

alter table public.rooms add column if not exists max_players int not null default 10 check (max_players between 2 and 10);
alter table public.rooms add column if not exists tiers int[] not null default '{0,1,2,3,4}';
alter table public.rooms add column if not exists tier_cap int not null default 2;
alter table public.rooms add column if not exists adjust_laps int not null default 1;

-- Agora um jogador pode ter várias respostas na mesma rodada.
alter table public.cards drop constraint if exists cards_room_id_round_author_id_key;
alter table public.cards add column if not exists slot int not null default 1;
create unique index if not exists cards_author_slot_idx on public.cards(room_id, round, author_id, slot);

drop function if exists public.create_room(text);
drop function if exists public.submit_answer(uuid, text);

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

  -- Recarga individual: 5 rodadas depois de zerar, o jogador ganha 1 de volta.
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
    -- Quem escreve uma resposta a mais reveza a cada rodada.
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

  -- Quem escolhe o tema: aleatório, evitando repetir quem escolheu na rodada anterior.
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

-- Cada jogador envia todas as suas respostas da rodada de uma vez, na ordem dos slots.
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

-- Subir ou descer 1 nível entre os Tiers que estão no quadro (com S, B e F, subir do B vai pro S).
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

-- Permissões: só as RPCs do jogo ficam expostas.
revoke all on all functions in schema public from public, anon, authenticated;
grant execute on function
  public.create_room(text, int), public.set_max_players(uuid, int), public.join_room(text, text), public.leave_room(uuid),
  public.start_game(uuid), public.choose_theme(uuid, int), public.reroll_themes(uuid), public.reassign_chooser(uuid),
  public.submit_answers(uuid, text[]), public.place_card(uuid, uuid, int), public.adjust_move(uuid, uuid, int, uuid),
  public.adjust_pass(uuid), public.skip_turn(uuid), public.reveal_next(uuid, boolean), public.next_round(uuid),
  public.end_match(uuid), public.new_match(uuid), public.get_state(uuid), public.is_member(uuid)
to authenticated;
