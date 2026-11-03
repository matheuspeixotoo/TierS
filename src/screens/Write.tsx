import { useState } from 'react'
import { Avatar, BigCard } from '../components/ui'
import { avatarUrl } from '../lib/supabase'
import { api } from '../lib/api'
import { TIER_COLORS, TIER_HINTS, TIERS, plural } from '../lib/game'
import type { GameState, Run } from '../lib/types'

const SHORT_HINTS = ['O topo absoluto', 'Muito bom', 'Ok, nem ama nem odeia', 'Meh', 'O fundo do poço']

export function Write({ s, run, busy }: { s: GameState; run: Run; busy: boolean }) {
  const mine = s.my_cards
  const [drafts, setDrafts] = useState<string[]>(() => mine.map((c) => c.answer ?? ''))
  const sent = mine.length > 0 && mine.every((c) => c.answer)
  const [editing, setEditing] = useState(!sent)
  const answered = s.players.filter((p) => p.answered).length
  const n = s.players.length
  const single = mine.length === 1
  const can = drafts.length === mine.length && drafts.every((d) => d.trim().length > 0) && !busy

  async function send() {
    if (!can) return
    const ok = await run(() => api.submitAnswers(s.room.id, drafts))
    if (ok) setEditing(false)
  }

  return (
    <section className="flex min-h-0 flex-1 items-center justify-center">
      <BigCard className={`grid gap-4 md:gap-9 ${single ? 'max-w-[960px] md:grid-cols-[5fr_7fr]' : 'max-w-[760px]'}`}>
        {single && (
          <div className="flex min-w-0 items-center gap-3.5 md:flex-col md:gap-4 md:text-center">
            <div
              className="flex h-16 w-16 flex-none items-center justify-center rounded-2xl border-[3px] border-ink font-display text-4xl text-ink md:h-[220px] md:w-[180px] md:rotate-3 md:rounded-[22px] md:border-4 md:text-[110px]"
              style={{ background: TIER_COLORS[mine[0].tier], boxShadow: '5px 5px 0 #1A1033' }}
            >
              {TIERS[mine[0].tier]}
            </div>
            <p className="m-0 text-[15px] font-extrabold">
              Tier {TIERS[mine[0].tier]}: {TIER_HINTS[mine[0].tier]}
            </p>
          </div>
        )}

        <div className="flex min-w-0 flex-col gap-3">
          <div className="flex min-w-0 flex-col gap-0.5">
            <span className="text-[13px] font-black tracking-wider text-muted">
              TEMA{!single && ` · ${plural(mine.length, 'RESPOSTA', 'RESPOSTAS')} PRA VOCÊ`}
            </span>
            <span className="font-display text-2xl leading-tight">{s.room.theme}</span>
          </div>

          {editing ? (
            <form
              className="flex flex-col gap-2.5"
              onSubmit={(e) => {
                e.preventDefault()
                void send()
              }}
            >
              {mine.map((c, i) => (
                <div key={c.id} className="flex items-center gap-2.5">
                  {!single && (
                    <span
                      className="pop flex h-12 w-12 flex-none items-center justify-center rounded-xl font-display text-2xl text-ink"
                      style={{ background: TIER_COLORS[c.tier], boxShadow: '3px 3px 0 #1A1033' }}
                      aria-hidden="true"
                    >
                      {TIERS[c.tier]}
                    </span>
                  )}
                  <div className="flex min-w-0 flex-1 flex-col gap-1">
                    <label htmlFor={`answer-${c.id}`} className={single ? 'text-[15px] font-black' : 'text-xs font-extrabold text-muted'}>
                      {single ? 'Sua resposta' : `Tier ${TIERS[c.tier]}: ${SHORT_HINTS[c.tier]}`}
                    </label>
                    <input
                      id={`answer-${c.id}`}
                      className={`field ${single ? '' : 'min-h-11! py-2! text-base!'}`}
                      value={drafts[i] ?? ''}
                      maxLength={40}
                      autoComplete="off"
                      placeholder={single ? 'Algo que combine com o seu Tier' : `Algo Tier ${TIERS[c.tier]}`}
                      onChange={(e) => setDrafts((d) => d.map((x, j) => (j === i ? e.target.value : x)))}
                    />
                  </div>
                </div>
              ))}
              <button type="submit" className="btn bg-sun text-xl" disabled={!can}>
                {busy ? 'Enviando...' : single ? 'Enviar resposta' : 'Enviar respostas'}
              </button>
            </form>
          ) : (
            <div className="flex flex-col gap-1.5 rounded-2xl border-[3px] border-ink bg-white p-3">
              <span className="text-[13px] font-black text-muted">{single ? 'SUA RESPOSTA' : 'SUAS RESPOSTAS'}</span>
              {mine.map((c) => (
                <span key={c.id} className="flex items-center gap-2 text-lg font-black">
                  <span className="flex h-7 w-7 flex-none items-center justify-center rounded-lg border-2 border-ink font-display text-sm" style={{ background: TIER_COLORS[c.tier] }}>
                    {TIERS[c.tier]}
                  </span>
                  <span className="min-w-0 truncate">{c.answer}</span>
                </span>
              ))}
              <button type="button" className="btn-ghost mt-1 self-start text-sm" onClick={() => setEditing(true)}>
                Editar
              </button>
            </div>
          )}

          <div className="flex flex-col gap-1.5">
            <span className="text-sm font-extrabold text-muted">
              {answered === n ? 'Todo mundo respondeu!' : `${answered} de ${n} já responderam`}
            </span>
            <ul className="m-0 flex list-none flex-wrap gap-1.5 p-0">
              {s.players.map((p) => (
                <li key={p.id} className={p.answered ? '' : 'opacity-35'} title={`${p.name}${p.answered ? ' respondeu' : ' está pensando'}`}>
                  <Avatar name={p.name} color={p.color} size={30} src={avatarUrl(p.avatar)} />
                </li>
              ))}
            </ul>
          </div>
        </div>
      </BigCard>
    </section>
  )
}
