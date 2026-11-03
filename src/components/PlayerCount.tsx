import { MAX_PLAYERS, MIN_PLAYERS, formationText } from '../lib/game'

/** Seletor do tamanho da sala (2 a 10) com o resumo da formação. */
export function PlayerCount({ value, min = MIN_PLAYERS, disabled, onChange }: { value: number; min?: number; disabled?: boolean; onChange: (n: number) => void }) {
  const opts = Array.from({ length: MAX_PLAYERS - MIN_PLAYERS + 1 }, (_, i) => i + MIN_PLAYERS)
  return (
    <div className="flex flex-col gap-2">
      <div className="grid grid-cols-9 gap-1" role="radiogroup" aria-label="Quantidade de jogadores">
        {opts.map((n) => {
          const on = n === value
          return (
            <button
              key={n}
              type="button"
              role="radio"
              aria-checked={on}
              aria-label={`${n} jogadores`}
              disabled={disabled || n < min}
              onClick={() => onChange(n)}
              className={`h-11 rounded-xl border-[3px] border-ink font-display text-base text-ink disabled:cursor-not-allowed disabled:opacity-35 ${
                on ? 'bg-sun' : 'bg-white'
              }`}
              style={on ? { boxShadow: '3px 3px 0 #1A1033' } : undefined}
            >
              {n}
            </button>
          )
        })}
      </div>
      <span className="text-[13px] font-extrabold text-muted">{formationText(value)}</span>
    </div>
  )
}
