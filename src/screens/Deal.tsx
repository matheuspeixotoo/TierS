import { useState } from 'react'
import { Avatar, BigCard, Waiting } from '../components/ui'
import { avatarUrl } from '../lib/supabase'
import { api } from '../lib/api'
import { TIER_COLORS, TIER_HINTS, TIERS, nameOf, plural } from '../lib/game'
import type { GameState, Run } from '../lib/types'

const OPTION_COLORS = ['#4CC9F0', '#F78FB3']

/** status 'deal': o jogador sorteado escolhe entre 2 temas. */
export function Deal({ s, run, busy }: { s: GameState; run: Run; busy: boolean }) {
  const { room } = s
  const chooser = s.players.find((p) => p.id === room.chooser)
  const mine = room.chooser === s.me
  const me = s.players.find((p) => p.id === s.me)
  const rerolls = me?.rerolls ?? 0
  const backAt = me?.rerolls_back_round ?? room.round + 5

  return (
    <section className="flex min-h-0 flex-1 items-center justify-center">
      <BigCard className="flex max-w-[720px] flex-col gap-4 md:gap-5">
        <span className="text-[13px] font-black tracking-wider text-muted">RODADA {room.round} · ESCOLHA DO TEMA</span>

        {mine ? (
          <>
            <h1 className="m-0 font-display text-[26px] leading-tight md:text-[40px]">Você escolhe o tema!</h1>
            <div className="grid gap-3 md:grid-cols-2 md:gap-4">
              {room.theme_options.map((t, i) => (
                <button
                  key={t.id}
                  type="button"
                  disabled={busy}
                  onClick={() => void run(() => api.chooseTheme(room.id, t.id))}
                  className={`btn land min-h-[84px] px-4 py-5 text-[22px] leading-tight md:min-h-[150px] md:text-[30px] ${i ? 'md:rotate-1' : 'md:-rotate-1'}`}
                  style={{ background: OPTION_COLORS[i] }}
                >
                  {t.name}
                </button>
              ))}
            </div>
            <div className="flex flex-col gap-1.5">
              <button
                type="button"
                className="btn bg-white text-[17px]"
                disabled={busy || rerolls <= 0}
                onClick={() => void run(() => api.rerollThemes(room.id))}
              >
                Sortear novamente ({rerolls})
              </button>
              <span className="text-sm font-extrabold text-muted">
                {rerolls > 0
                  ? `Você tem ${plural(rerolls, 'sorteio', 'sorteios')}. Se zerar, ganha 1 de volta 5 rodadas depois.`
                  : `Acabaram seus sorteios: escolha um dos dois. Na rodada ${backAt} você ganha 1 de volta.`}
              </span>
            </div>
          </>
        ) : (
          <>
            <div className="flex items-center gap-3.5">
              {chooser && <Avatar name={chooser.name} color={chooser.color} size={56} src={avatarUrl(chooser.avatar)} />}
              <h1 className="m-0 font-display text-[24px] leading-tight md:text-[36px]">{nameOf(s, room.chooser)} está escolhendo o tema...</h1>
            </div>
            <Waiting>O tema aparece assim que a escolha for feita.</Waiting>
            {s.is_host && (
              <button type="button" className="btn-ghost self-start text-sm" disabled={busy} onClick={() => void run(() => api.reassignChooser(room.id))}>
                {nameOf(s, room.chooser)} sumiu? Sortear outra pessoa
              </button>
            )}
          </>
        )}
      </BigCard>
    </section>
  )
}

/** Quando o tema chega: mostra o tema escolhido e depois o Tier secreto. */
export function Intro({ s, onDone, chooserName }: { s: GameState; onDone: () => void; chooserName: string }) {
  const [flipped, setFlipped] = useState(false)
  const mine = s.my_cards
  const tier = mine[0]?.tier ?? 0
  const many = mine.length > 1

  return (
    <section className="flex min-h-0 flex-1 items-center justify-center">
      <BigCard className="grid max-w-[960px] items-center gap-4 md:grid-cols-2 md:gap-9">
        <div className="flex min-w-0 flex-col gap-4">
          <span className="text-[13px] font-black tracking-wider text-muted">RODADA {s.room.round} · O TEMA É</span>
          <div
            className="land rounded-[20px] border-[3px] border-ink bg-sky px-4 py-5 text-center font-display text-2xl leading-tight text-ink md:py-9 md:text-[40px]"
            style={{ boxShadow: '5px 5px 0 #1A1033' }}
          >
            {s.room.theme}
          </div>
          <span className="text-sm font-extrabold text-muted">Escolhido por {chooserName}</span>
        </div>

        <div className="flex min-w-0 flex-col items-center gap-3">
          <span className="text-[13px] font-black tracking-wider text-muted">{many ? 'SEUS TIERS SECRETOS' : 'SEU TIER SECRETO'}</span>
          {!flipped ? (
            <button
              type="button"
              aria-label="Revelar meu Tier"
              onClick={() => setFlipped(true)}
              className="flex h-40 w-[130px] -rotate-3 cursor-pointer flex-col items-center justify-center gap-1.5 rounded-[22px] border-4 border-ink bg-ink font-display text-6xl text-sun md:h-[220px] md:w-[180px] md:text-[80px]"
              style={{ boxShadow: '6px 6px 0 #FF6B6B' }}
            >
              ?<span className="font-sans text-sm font-black text-cream">Toque pra ver</span>
            </button>
          ) : (
            <>
              {many ? (
                <>
                  <div className="flex flex-wrap justify-center gap-2.5">
                    {mine.map((c, i) => (
                      <div
                        key={c.id}
                        className="flip-in flex h-24 w-[68px] items-center justify-center rounded-2xl border-4 border-ink font-display text-5xl text-ink md:h-32 md:w-[92px] md:text-6xl"
                        style={{ background: TIER_COLORS[c.tier], boxShadow: '4px 4px 0 #1A1033', animationDelay: `${i * 80}ms` }}
                      >
                        {TIERS[c.tier]}
                      </div>
                    ))}
                  </div>
                  <p className="m-0 max-w-[380px] text-center text-[15px] font-extrabold">
                    Você vai escrever {mine.length} respostas, uma pra cada Tier. Não conta pra ninguém!
                  </p>
                </>
              ) : (
                <>
                  <div
                    className="flip-in flex h-40 w-[130px] items-center justify-center rounded-[22px] border-4 border-ink font-display text-[80px] text-ink md:h-[220px] md:w-[180px] md:text-[110px]"
                    style={{ background: TIER_COLORS[tier], boxShadow: '6px 6px 0 #1A1033' }}
                  >
                    {TIERS[tier]}
                  </div>
                  <p className="m-0 max-w-[380px] text-center text-[15px] font-extrabold">
                    Tier {TIERS[tier]}: {TIER_HINTS[tier]} Não conta pra ninguém!
                  </p>
                </>
              )}
              <button type="button" className="btn self-stretch bg-sun text-lg" onClick={onDone}>
                {many ? 'Escrever minhas respostas' : 'Escrever minha resposta'}
              </button>
            </>
          )}
        </div>
      </BigCard>
    </section>
  )
}
