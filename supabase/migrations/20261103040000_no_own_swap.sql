-- =====================================================================
-- TierS: ninguém mexe na própria resposta, nem por troca.
-- Mover a própria resposta já era bloqueado; agora a troca (quando o Tier
-- de destino está cheio) também não pode envolver uma resposta sua.
-- =====================================================================

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
