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
