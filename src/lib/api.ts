import { supabase } from './supabase'
import type { GameState, Profile, RankingRow } from './types'

function clean(message: string): string {
  // Mensagens das funções SQL já vêm em português; só tiramos ruído técnico.
  return message.replace(/^.*?ERROR:\s*/i, '').trim() || 'Algo deu errado. Tente de novo.'
}

async function call<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) {
    if (error.message.includes('Failed to fetch')) throw new Error('Sem conexão. Confira sua internet.')
    throw new Error(clean(error.message))
  }
  return data as T
}

export const api = {
  getState: (room: string) => call<GameState>('get_state', { p_room: room }),
  createRoom: (name: string, max: number) => call<string>('create_room', { p_name: name, p_max: max }),
  setMaxPlayers: (room: string, max: number) => call<void>('set_max_players', { p_room: room, p_max: max }),
  joinRoom: (code: string, name: string) => call<string>('join_room', { p_code: code, p_name: name }),
  leaveRoom: (room: string) => call<void>('leave_room', { p_room: room }),
  startGame: (room: string) => call<void>('start_game', { p_room: room }),
  chooseTheme: (room: string, theme: number) => call<void>('choose_theme', { p_room: room, p_theme: theme }),
  rerollThemes: (room: string) => call<void>('reroll_themes', { p_room: room }),
  reassignChooser: (room: string) => call<void>('reassign_chooser', { p_room: room }),
  submitAnswers: (room: string, texts: string[]) => call<void>('submit_answers', { p_room: room, p_texts: texts }),
  placeCard: (room: string, card: string, tier: number) => call<void>('place_card', { p_room: room, p_card: card, p_tier: tier }),
  adjustMove: (room: string, card: string, dir: number, swap: string | null) =>
    call<void>('adjust_move', { p_room: room, p_card: card, p_dir: dir, p_swap: swap }),
  adjustPass: (room: string) => call<void>('adjust_pass', { p_room: room }),
  skipTurn: (room: string) => call<void>('skip_turn', { p_room: room }),
  revealNext: (room: string, all: boolean) => call<void>('reveal_next', { p_room: room, p_all: all }),
  nextRound: (room: string) => call<void>('next_round', { p_room: room }),
  endMatch: (room: string) => call<void>('end_match', { p_room: room }),
  newMatch: (room: string) => call<void>('new_match', { p_room: room }),

  // Conta e perfil
  getProfile: (user?: string) => call<Profile | null>('get_profile', { p_user: user ?? null }),
  saveProfile: (nick: string, first: string, last: string) =>
    call<Profile>('save_profile', { p_nick: nick, p_first: first, p_last: last }),
  setAvatar: (path: string | null) => call<void>('set_avatar', { p_path: path }),
  getRanking: (limit = 50) => call<RankingRow[]>('get_ranking', { p_limit: limit }),
}
