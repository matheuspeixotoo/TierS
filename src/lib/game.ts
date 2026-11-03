import type { GameState, Player } from './types'

export const TIERS = ['S', 'A', 'B', 'C', 'F'] as const
export const TIER_COLORS = ['#FF6B6B', '#FFA94D', '#FFD93D', '#6BCB77', '#9D8CFF']
export const TIER_HINTS = [
  'O topo absoluto. Algo que todo mundo vai concordar que é incrível.',
  'Muito bom, mas não chega a ser lendário.',
  'Ok. Ninguém ama, ninguém odeia.',
  'Meh. Dá pra encarar, mas ninguém escolhe.',
  'O fundo do poço. Ninguém defende isso.',
]

export const HOW_TO = [
  'Alguém é sorteado pra escolher o tema e cada um recebe um Tier secreto.',
  'Escreva algo do tema que combine com o seu Tier.',
  'Na sua vez, coloque a resposta de alguém no quadro.',
  'Cada um pode subir ou descer uma resposta em 1 nível.',
  'Revelação: vocês gabaritaram?',
]

export const MIN_PLAYERS = 2
export const MAX_PLAYERS = 10

/** Mesma tabela do servidor (_formation): Tiers no quadro e respostas por Tier. */
export function formation(n: number) {
  const tiers = n === 3 || n === 6 ? [0, 2, 4] : n === 4 || n === 7 || n === 8 ? [0, 1, 2, 4] : [0, 1, 2, 3, 4]
  const cap = n === 3 ? 3 : n === 6 ? 4 : 2
  const total = tiers.length * cap
  const base = Math.floor(total / n)
  const extra = total % n
  return { tiers, cap, total, base, extra }
}

export function formationText(n: number) {
  const f = formation(n)
  const letters = f.tiers.map((t) => TIERS[t]).join(', ')
  const each = f.extra
    ? `${plural(f.base, 'resposta', 'respostas')} por pessoa (e um jogador escreve ${f.base + 1}, revezando)`
    : n === 2
      ? '5 respostas por pessoa, uma de cada Tier'
      : `${plural(f.base, 'resposta', 'respostas')} por pessoa`
  return `Tiers ${letters} · ${each}`
}

export function plural(n: number, one: string, many: string) {
  return `${n} ${n === 1 ? one : many}`
}

export function signed(n: number) {
  return n > 0 ? `+${n}` : n < 0 ? `−${Math.abs(n)}` : '0'
}

export function ranked(players: Player[]) {
  return [...players].sort((a, b) => b.score - a.score || b.hits - a.hits || a.misses - b.misses || a.seat - b.seat)
}

export function nameOf(s: GameState, id: string | null | undefined) {
  if (!id) return '...'
  if (id === s.me) return 'Você'
  return s.players.find((p) => p.id === id)?.name ?? '...'
}

export function hostName(s: GameState) {
  return s.is_host ? 'Você' : (s.players.find((p) => p.id === s.room.host_player)?.name ?? 'o host')
}

export function initials(name: string) {
  return name.trim().slice(0, 2).toUpperCase()
}

export function inviteLink(code: string) {
  return `${window.location.origin}${window.location.pathname}?sala=${code}`
}

export async function shareInvite(code: string): Promise<'shared' | 'copied' | 'failed'> {
  const url = inviteLink(code)
  const text = `Bora jogar TierS! Código da sala: ${code}`
  try {
    if (navigator.share) {
      await navigator.share({ title: 'TierS', text, url })
      return 'shared'
    }
  } catch (e) {
    if ((e as Error).name === 'AbortError') return 'failed'
  }
  try {
    await navigator.clipboard.writeText(`${text}\n${url}`)
    return 'copied'
  } catch {
    return 'failed'
  }
}
