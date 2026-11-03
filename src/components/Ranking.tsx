import { ranked, signed } from '../lib/game'
import type { GameState } from '../lib/types'

const MEDAL = ['#FFD93D', '#E4DED3', '#F4A261']

/** Placar. `compact` usa duas colunas para caber 10 jogadores sem rolar. */
export function Ranking({ s, compact, showDelta }: { s: GameState; compact: boolean; showDelta: boolean }) {
  const list = ranked(s.players)
  return (
    <ol className={`m-0 grid list-none gap-1.5 p-0 ${compact ? 'grid-cols-2' : 'grid-cols-1'}`}>
      {list.map((p, i) => {
        const d = p.last_delta ?? 0
        return (
          <li
            key={p.id}
            className={`flex min-w-0 items-center gap-1.5 rounded-[10px] border-2 border-ink ${compact ? 'px-1.5 py-1' : 'px-2 py-1.5'} ${
              p.id === s.me ? 'bg-lilac' : 'bg-white'
            }`}
          >
            <span
              className="flex h-6 w-6 flex-none items-center justify-center rounded-lg border-2 border-ink font-display text-xs text-ink"
              style={{ background: MEDAL[i] ?? '#FFFFFF' }}
            >
              {i + 1}
            </span>
            <span className={`min-w-0 flex-1 truncate font-black ${compact ? 'text-[13px]' : 'text-[15px]'}`}>{p.id === s.me ? 'Você' : p.name}</span>
            {showDelta && p.last_delta !== null && (
              <span
                className="flex-none rounded-full border-2 border-ink px-1.5 text-[11px] font-black text-ink"
                style={{ background: d > 0 ? '#6BCB77' : d < 0 ? '#FF6B6B' : '#E4DED3' }}
              >
                {signed(d)}
              </span>
            )}
            <span className={`flex-none whitespace-nowrap font-display ${compact ? 'text-[13px]' : 'text-[15px]'}`}>
              {signed(p.score).replace('+', '')}
              {!compact && ' pts'}
            </span>
          </li>
        )
      })}
    </ol>
  )
}
