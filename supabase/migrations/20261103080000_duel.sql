-- =====================================================================
-- TierS: modo dupla (2 jogadores)
-- Em dupla cada um escreve 5 respostas, uma de cada Tier, e o quadro tem
-- 2 lugares por Tier. Duas regras só para esse modo:
--  1. No posicionamento, cada Tier recebe no máximo UMA resposta de cada
--     jogador. Sem isso, duas respostas da mesma pessoa no mesmo Tier
--     travavam os ajustes.
--  2. No ajuste, a resposta pode ir para QUALQUER Tier (não só 1 nível),
--     trocando de lugar com a resposta da outra pessoa que estiver lá.
--     Só dá pra mexer (e trocar com) respostas que VOCÊ posicionou: em
--     dupla são exatamente as respostas da outra pessoa, já que cada um
--     posiciona todas as do outro.
-- A pontuação dos ajustes já compara a distância até o Tier real, então
-- um movimento de vários níveis conta como aproximou ou afastou.
-- =====================================================================

create or replace function public._is_duel(r public.rooms) returns boolean language sql immutable as $$
  select coalesce(array_length(r.turn_order, 1), 0) = 2;
$$;

create or replace function public.place_card(p_room uuid, p_card uuid, p_tier int) returns void
language plpgsql security definer set search_path = public as $$
declare
  r rooms := _lock_room(p_room);
  me players := _me(p_room);
  c cards;
  v_seq int;
  v_author text;
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
  if _is_duel(r) and exists (select 1 from cards where room_id = p_room and round = r.round and placed_tier = p_tier and author_id = c.author_id) then
    select name into v_author from players where id = c.author_id;
    raise exception 'O Tier % já tem uma resposta de %. Em dupla, cada Tier leva uma resposta de cada um.', _tier_letter(p_tier), coalesce(v_author, 'quem escreveu');
  end if;
  select coalesce(max(placed_seq), 0) + 1 into v_seq from cards where room_id = p_room and round = r.round;
  update cards set placed_tier = p_tier, placed_init = p_tier, placed_by = me.id, placed_seq = v_seq,
    last_by = me.id, last_verb = 'colocado'
  where id = c.id;
  perform _log(p_room, me.name || ' colocou “' || c.answer || '” no Tier ' || _tier_letter(p_tier));
  perform _advance_place(p_room);
  perform _bump(p_room);
end $$;

-- p_dir é quantos níveis andar entre os Tiers do quadro (negativo sobe).
-- Fora do modo dupla continua valendo só -1 ou 1.
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
  if p_dir is null or p_dir = 0 or (not _is_duel(r) and p_dir not in (-1, 1)) then raise exception 'Movimento inválido'; end if;
  select * into c from cards where id = p_card and room_id = p_room and round = r.round for update;
  if not found then raise exception 'Resposta não encontrada'; end if;
  if c.author_id = me.id then raise exception 'Você não pode mexer na sua própria resposta'; end if;
  if _is_duel(r) and c.placed_by is distinct from me.id then raise exception 'Em dupla, você só mexe nas respostas que você posicionou'; end if;
  v_from := c.placed_tier;
  v_to := r.tiers[array_position(r.tiers, v_from) + p_dir];
  if v_to is null then raise exception 'Não dá pra mover pra fora do quadro'; end if;

  v_txt := me.name || case when p_dir < 0 then ' subiu “' else ' desceu “' end || c.answer || '” para o Tier ' || _tier_letter(v_to);
  if (select count(*) from cards where room_id = p_room and round = r.round and placed_tier = v_to) >= r.tier_cap then
    if p_swap is null then raise exception 'O Tier % está cheio: escolha com quem trocar', _tier_letter(v_to); end if;
    select * into o from cards where id = p_swap and room_id = p_room and round = r.round and placed_tier = v_to for update;
    if not found then raise exception 'Escolha uma resposta do Tier % para trocar', _tier_letter(v_to); end if;
    if o.author_id = me.id then raise exception 'Você não pode trocar com a sua própria resposta'; end if;
    if _is_duel(r) and o.placed_by is distinct from me.id then raise exception 'Em dupla, você só troca com respostas que você posicionou'; end if;
    update cards set placed_tier = v_from, last_by = me.id, last_verb = 'trocado' where id = o.id;
    insert into moves(room_id, round, by_player, card_id, from_tier, to_tier) values (p_room, r.round, me.id, o.id, v_to, v_from);
    v_txt := v_txt || ' (trocou com “' || o.answer || '”)';
  end if;
  if _is_duel(r) and exists (select 1 from cards where room_id = p_room and round = r.round and placed_tier = v_to and author_id = c.author_id and id <> c.id) then
    raise exception 'O Tier % já tem outra resposta dessa pessoa', _tier_letter(v_to);
  end if;
  update cards set placed_tier = v_to, last_by = me.id, last_verb = 'movido' where id = c.id;
  insert into moves(room_id, round, by_player, card_id, from_tier, to_tier) values (p_room, r.round, me.id, c.id, v_from, v_to);
  perform _log(p_room, v_txt);
  perform _advance_adjust(p_room);
  perform _bump(p_room);
end $$;

revoke all on function public._is_duel(public.rooms) from public, anon, authenticated;
