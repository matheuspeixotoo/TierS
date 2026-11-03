-- =====================================================================
-- TierS: recarga individual do "Sortear novamente"
-- Quem zera os sorteios ganha 1 de volta 5 rodadas depois de zerar
-- (zerou na rodada 4, recebe na rodada 9). Quem ainda tem algum não ganha nada.
-- =====================================================================

alter table public.players add column if not exists zeroed_round int;

create or replace function public._deal_round(p_room uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  r rooms;
  v_round int;
  v_pool int[];
  v_card uuid;
  v_chooser uuid;
  v_options int[];
  i int := 1;
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

  select array_agg(t order by random()) into v_pool from unnest(array[0,0,1,1,2,2,3,3,4,4]) t;
  for p in select * from players where room_id = p_room order by seat loop
    insert into cards(room_id, round, author_id) values (p_room, v_round, p.id) returning id into v_card;
    insert into card_secrets(card_id, room_id, user_id, tier) values (v_card, p_room, p.user_id, v_pool[i]);
    i := i + 1;
  end loop;

  -- Quem escolhe: aleatório, evitando repetir quem escolheu na rodada anterior.
  select id into v_chooser from players
    where room_id = p_room and id is distinct from r.chooser
    order by random() limit 1;
  if v_chooser is null then
    select id into v_chooser from players where room_id = p_room order by random() limit 1;
  end if;
  v_options := _theme_options(array[coalesce(r.last_theme_id, -1)]);

  update rooms set status = 'deal', theme_id = null, turn_order = '{}', turn = 0, revealed = 0, round_scored = false,
    chooser = v_chooser, theme_options = v_options
  where id = p_room;
  update players set last_delta = null, last_bad_place = 0, last_bad_move = 0 where room_id = p_room;
  perform _log(p_room, (select name from players where id = v_chooser) || ' vai escolher o tema da rodada ' || v_round);
end $$;

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
  update players set score = 0, hits = 0, misses = 0, rerolls = 3, zeroed_round = null where room_id = p_room;
  update rooms set round = 0, rounds_done = 0, gabaritos = 0, last_theme_id = null, chooser = null where id = p_room;
  perform _deal_round(p_room);
  perform _log(p_room, 'A partida começou!');
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
      'host_player', (select id from players where room_id = p_room and user_id = r.host_user),
      'chooser', r.chooser,
      -- As opções só aparecem para quem escolhe.
      'theme_options', case when r.chooser = me.id then coalesce((
        select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name) order by array_position(r.theme_options, t.id))
        from themes t where t.id = any(r.theme_options)), '[]'::jsonb) else '[]'::jsonb end
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
        'last_bad_place', p.last_bad_place, 'last_bad_move', p.last_bad_move, 'rerolls', p.rerolls,
        'rerolls_back_round', case when p.rerolls = 0 and p.zeroed_round is not null then p.zeroed_round + 5 end,
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
