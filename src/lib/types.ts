export type Status = 'lobby' | 'deal' | 'write' | 'place' | 'adjust' | 'reveal' | 'final'

export interface Player {
  id: string
  name: string
  color: string
  seat: number
  score: number
  hits: number
  misses: number
  last_delta: number | null
  last_bad_place: number
  last_bad_move: number
  rerolls: number
  /** Rodada em que o jogador ganha 1 "Sortear novamente" de volta (só quando está zerado). */
  rerolls_back_round: number | null
  /** Quantas respostas o jogador escreve nesta rodada. */
  cards: number
  answered: boolean
  /** Caminho da foto de perfil no bucket "avatars" (só quem tem conta). */
  avatar: string | null
  registered: boolean
}

export interface Card {
  id: string
  author_id: string
  answer: string | null
  placed_tier: number | null
  placed_seq: number | null
  last_by: string | null
  last_verb: string | null
  revealed_tier: number | null
}

export interface RoomInfo {
  id: string
  status: Status
  round: number
  theme: string | null
  turn_order: string[]
  turn: number
  revealed: number
  round_scored: boolean
  rounds_done: number
  gabaritos: number
  version: number
  current_player: string | null
  host_player: string | null
  max_players: number
  /** Tiers que estão no quadro nesta formação (0 = S ... 4 = F). */
  tiers: number[]
  /** Quantas respostas cabem em cada Tier. */
  tier_cap: number
  /** Quantas voltas de ajuste a rodada tem. */
  adjust_laps: number
  chooser: string | null
  /** Só vem preenchido para quem está escolhendo o tema. */
  theme_options: { id: number; name: string }[]
}

export interface MyCard {
  id: string
  slot: number
  tier: number
  answer: string | null
}

export interface GameEvent {
  id: number
  text: string
}

export interface GameState {
  room: RoomInfo
  code: string | null
  is_host: boolean
  me: string
  /** Suas respostas da rodada, com o Tier secreto de cada uma. */
  my_cards: MyCard[]
  players: Player[]
  cards: Card[]
  events: GameEvent[]
}

/** Executa uma ação no servidor, mostrando erro em toast e atualizando o estado. */
export type Run = (fn: () => Promise<unknown>) => Promise<boolean>

/** Estatísticas acumuladas de uma conta (partidas encerradas pelo host). */
export interface ProfileStats {
  matches: number
  wins: number
  points: number
  hits: number
  misses: number
  best: number
  gabaritos: number
}

export interface MatchSummary {
  id: string
  ended_at: string
  players_count: number
  rounds_done: number
  gabaritos: number
  position: number
  score: number
  hits: number
  misses: number
  winner: string | null
}

export interface Profile {
  user_id: string
  nick: string
  /** Só vem para o próprio dono do perfil. */
  first_name: string | null
  last_name: string | null
  /** Código de 6 letras para outros te adicionarem. Só vem para o dono. */
  friend_code: string | null
  /** Quantidade de amigos. */
  friends: number
  avatar_path: string | null
  created_at: string
  is_me: boolean
  /** Posição no ranking entre amigos (null para quem ainda não jogou). */
  rank: number | null
  stats: ProfileStats
  history: MatchSummary[]
}

export interface Friend {
  user_id: string
  nick: string
  avatar_path: string | null
  since: string
}

export interface RankingRow {
  user_id: string
  nick: string
  avatar_path: string | null
  is_me: boolean
  matches: number
  wins: number
  points: number
  hits: number
  misses: number
}
