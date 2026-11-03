import { useEffect, useMemo, useState } from 'react'
import { Avatar, TierBlock, Waiting } from '../components/ui'
import { avatarUrl } from '../lib/supabase'
import { Ranking } from '../components/Ranking'
import { api } from '../lib/api'
import { TIER_COLORS, TIERS, hostName, nameOf, plural } from '../lib/game'
import type { Card, GameState, Run } from '../lib/types'

type Tab = 'jogada' | 'resultado' | 'ranking' | 'historico'
const TABS: [Tab, string][] = [
  ['jogada', 'Jogada'],
  ['resultado', 'Resultado'],
  ['ranking', 'Ranking'],
  ['historico', 'Histórico'],
]

export function Game({ s, run, busy }: { s: GameState; run: Run; busy: boolean }) {
  const { room } = s
  const status = room.status
  const cur = room.current_player
  const myTurn = (status === 'place' || status === 'adjust') && cur === s.me
  const n = s.players.length
  const boardTiers = room.tiers
  const cap = room.tier_cap
  const adjustTurns = n * room.adjust_laps
  const total = s.cards.length
  // Quadro com 3 ou 4 respostas por fileira: cartas mais estreitas e mais altas.
  const dense = cap >= 3
  const tall = boardTiers.length <= 3

  const [tab, setTab] = useState<Tab>('jogada')
  const [sel, setSel] = useState<string | null>(null)
  const [pending, setPending] = useState<{ card: string; dir: number; to: number } | null>(null)
  const [seenResult, setSeenResult] = useState(0)

  // Limpa a seleção sempre que a vez ou a fase mudam.
  useEffect(() => {
    setSel(null)
    setPending(null)
  }, [status, room.turn, room.round])
  useEffect(() => setTab('jogada'), [room.round])

  const tiers = useMemo(() => {
    const rows: Card[][] = [[], [], [], [], []]
    for (const c of s.cards) if (c.placed_tier !== null) rows[c.placed_tier].push(c)
    rows.forEach((r) => r.sort((a, b) => (a.placed_seq ?? 0) - (b.placed_seq ?? 0)))
    return rows
  }, [s.cards])
  const unplaced = s.cards.filter((c) => c.placed_tier === null)
  const selCard = s.cards.find((c) => c.id === sel) ?? null
  const scored = room.round_scored
  const correct = s.cards.filter((c) => c.revealed_tier !== null && c.revealed_tier === c.placed_tier).length
  const all = scored && correct === total
  const resultDot = scored && seenResult !== room.round && tab !== 'resultado'

  const act = (fn: () => Promise<unknown>) => void run(fn)
  const place = (tier: number) => sel && act(() => api.placeCard(room.id, sel, tier))
  // Pra onde a resposta selecionada pode ir: Tier vizinho com espaço, ou cheio mas com alguma resposta de outra pessoa pra trocar.
  const canMove = (dir: number) => {
    if (!selCard || selCard.placed_tier === null) return false
    const to = boardTiers[boardTiers.indexOf(selCard.placed_tier) + dir]
    if (to === undefined) return false
    return tiers[to].length < cap || tiers[to].some((o) => o.author_id !== s.me)
  }
  const move = (dir: number) => {
    if (!selCard || selCard.placed_tier === null) return
    const to = boardTiers[boardTiers.indexOf(selCard.placed_tier) + dir]
    if (to === undefined) return
    if (tiers[to].length >= cap) setPending({ card: selCard.id, dir, to })
    else act(() => api.adjustMove(room.id, selCard.id, dir, null))
  }

  // ---------- textos da vez ----------
  const phase = status === 'place' ? 'POSICIONAMENTO' : status === 'adjust' ? `AJUSTES ${Math.min(room.turn + 1, adjustTurns)}/${adjustTurns}` : 'REVELAÇÃO'
  let turnTitle = 'Hora da verdade'
  let instruction = 'Os Tiers de cada resposta vão aparecer, do S ao F.'
  if (status === 'place' || status === 'adjust') {
    turnTitle = myTurn ? 'É a sua vez!' : `É a vez de ${nameOf(s, cur)}`
    if (status === 'place') {
      instruction = myTurn
        ? sel
          ? 'Agora escolha o Tier. Também dá pra tocar num espaço vazio do quadro.'
          : 'Escolha uma resposta e depois o Tier dela.'
        : `${nameOf(s, cur)} está pensando onde colocar...`
    } else {
      instruction = myTurn ? 'Toque numa resposta do quadro para subir ou descer 1 nível. Ou passe a vez.' : `${nameOf(s, cur)} está analisando o quadro...`
    }
  }
  const turnBg = myTurn ? 'bg-sun' : status === 'reveal' ? 'bg-bubblegum' : 'bg-sky'

  const skipBtn =
    s.is_host && cur && cur !== s.me ? (
      <button type="button" className="btn-ghost text-sm" disabled={busy} onClick={() => act(() => api.skipTurn(room.id))}>
        Pular a vez de {nameOf(s, cur)}
      </button>
    ) : null

  return (
    <section className="flex min-h-0 flex-1 flex-col gap-2 md:grid md:grid-cols-[minmax(0,1fr)_320px] md:grid-rows-[auto_minmax(0,1fr)] md:gap-4 lg:grid-cols-[260px_minmax(0,1fr)_360px] lg:grid-rows-[minmax(0,1fr)] lg:gap-5">
      {/* ---------- vez ---------- */}
      <div className="flex min-w-0 flex-none flex-col gap-3 md:col-start-2 md:row-start-1 lg:col-start-1">
        <div className={`pop flex flex-col rounded-[14px] px-3 py-1.5 text-ink md:gap-1 md:rounded-[20px] md:p-4 ${turnBg}`} aria-live="polite">
          <span className="text-xs font-black tracking-wider">
            RODADA {room.round} · {phase}
          </span>
          <span className="font-display text-lg leading-tight md:text-[26px]">{turnTitle}</span>
          <span className="hidden text-[15px] font-bold md:block">{instruction}</span>
        </div>
        <ul className="m-0 hidden list-none flex-wrap gap-2 p-1 md:flex">
          {s.players.map((p) => (
            <li key={p.id}>
              <Avatar name={p.name} color={p.color} size={40} ring={p.id === cur} label={p.id === s.me ? 'Você' : p.name} src={avatarUrl(p.avatar)} />
            </li>
          ))}
        </ul>
      </div>

      {/* ---------- quadro ---------- */}
      <div className="flex min-h-0 min-w-0 flex-1 flex-col gap-1.5 md:col-start-1 md:row-span-2 md:row-start-1 md:gap-2.5 lg:col-start-2 lg:row-span-1">
        <div className="flex min-w-0 flex-none items-baseline gap-2.5">
          <span className="text-xs font-black tracking-wider text-haze">TEMA</span>
          <span className="truncate font-display text-lg leading-tight text-cream md:text-[26px] lg:text-[32px]" style={{ textShadow: '3px 3px 0 #1A1033' }}>
            {room.theme}
          </span>
        </div>
        <div
          className="flex min-h-0 flex-1 flex-col gap-1.5 rounded-[18px] border-[3px] border-ink bg-night p-2 md:gap-2.5 md:rounded-3xl md:p-3 lg:gap-3 lg:p-3.5"
          style={{ boxShadow: '6px 6px 0 #120A2E' }}
        >
          {boardTiers.map((t) => (
            <div key={t} className="flex min-h-0 flex-1 gap-1.5 md:gap-2.5 lg:gap-3">
              <TierBlock
                tier={t}
                className="w-[46px] flex-none rounded-[10px] text-[26px] md:w-[76px] md:rounded-2xl md:text-[42px] lg:w-[104px] lg:text-[56px]"
                style={{ boxShadow: '3px 3px 0 #120A2E' }}
              />
              {Array.from({ length: cap }, (_, k) => {
                const letter = TIERS[t]
                const c = tiers[t][k]
                if (!c) {
                  const canDrop = status === 'place' && myTurn && !!sel
                  return (
                    <button
                      key={k}
                      type="button"
                      disabled={!canDrop || busy}
                      onClick={() => place(t)}
                      aria-label={`Espaço vazio no Tier ${letter}`}
                      className={`flex min-h-0 min-w-0 flex-1 items-center justify-center rounded-[10px] border-[3px] text-center text-[13px] font-black md:rounded-2xl md:text-base lg:text-[19px] ${
                        canDrop ? 'cursor-pointer border-sun bg-sun/20 text-sun' : 'border-dashed border-white/30 bg-white/5 text-white/55'
                      }`}
                    >
                      {canDrop ? 'Colocar aqui' : 'vazio'}
                    </button>
                  )
                }
                const own = c.author_id === s.me
                const selectable = status === 'adjust' && myTurn && !own && !pending
                const isSel = sel === c.id
                const rev = c.revealed_tier !== null
                const right = rev && c.revealed_tier === t
                const bg = isSel ? '#FFFFFF' : rev ? (right ? '#C8F2CF' : '#FFD0D0') : own ? '#E9E1FF' : '#FFF6E5'
                const sub = status === 'reveal' ? `de ${nameOf(s, c.author_id)}` : own ? 'Sua resposta' : c.last_by ? `${c.last_verb} por ${nameOf(s, c.last_by)}` : ''
                return (
                  <button
                    key={c.id}
                    type="button"
                    disabled={!selectable || busy}
                    onClick={() => setSel(isSel ? null : c.id)}
                    aria-pressed={isSel}
                    aria-label={`${c.answer} no Tier ${letter}${rev ? `, era Tier ${TIERS[c.revealed_tier!]}` : ''}`}
                    className={`flex min-h-0 min-w-0 flex-1 flex-col justify-center gap-0.5 overflow-hidden rounded-[10px] border-[3px] border-ink ${dense ? "px-1.5" : "px-2"} py-1 text-left text-ink md:rounded-2xl md:px-3.5 md:py-2.5 ${
                      selectable ? 'cursor-pointer' : 'cursor-default'
                    }`}
                    style={{ background: bg, boxShadow: isSel ? '0 0 0 4px #4CC9F0' : '3px 3px 0 #120A2E' }}
                  >
                    <span className={`${rev ? (tall ? 'clamp-2 md:clamp-3' : 'clamp-1 md:clamp-2') : tall ? 'clamp-3' : 'clamp-2'} ${dense ? 'text-xs' : 'text-[13px]'} font-black leading-tight md:text-base lg:text-[19px]`}>{c.answer}</span>
                    {!rev && sub && <span className="hidden max-w-full truncate text-xs font-extrabold opacity-80 md:block">{sub}</span>}
                    {rev && (
                      <span
                        className="self-start whitespace-nowrap rounded-full border-2 border-ink px-2 text-[11px] font-black md:text-xs"
                        style={{ background: TIER_COLORS[c.revealed_tier!] }}
                      >
                        {right ? (dense ? `✓ ${TIERS[c.revealed_tier!]}` : `Certo! ${TIERS[c.revealed_tier!]}`) : `Era ${TIERS[c.revealed_tier!]}`}
                      </span>
                    )}
                  </button>
                )
              })}
            </div>
          ))}
        </div>
      </div>

      {/* ---------- painel com abas ---------- */}
      <div
        className="pop flex h-[min(300px,40dvh)] min-h-0 min-w-0 flex-none flex-col gap-2 rounded-[18px] bg-cream p-2 text-ink md:col-start-2 md:row-start-2 md:h-auto md:gap-3 md:rounded-[20px] md:p-3 lg:col-start-3 lg:row-start-1"
      >
        <div role="tablist" aria-label="Painel da partida" className="grid flex-none grid-cols-4 gap-1 rounded-[14px] bg-ink p-1">
          {TABS.map(([key, label]) => {
            const on = tab === key
            return (
              <button
                key={key}
                type="button"
                role="tab"
                aria-selected={on}
                onClick={() => {
                  setTab(key)
                  if (key === 'resultado') setSeenResult(room.round)
                }}
                className={`min-h-9 whitespace-nowrap rounded-[10px] px-0.5 text-xs font-black md:min-h-10 md:text-[13px] ${on ? 'bg-sun text-ink' : 'text-lilac'}`}
              >
                {label}
                {key === 'resultado' && resultDot && <span className="ml-1 inline-block h-2 w-2 rounded-full bg-coral align-middle" aria-label="novo" />}
              </button>
            )
          })}
        </div>

        <div role="tabpanel" className="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto p-0.5 md:gap-2.5">
          {tab === 'jogada' && (
            <>
              {status === 'place' &&
                (myTurn && selCard ? (
                  <>
                    <span className="text-[15px] font-black">Em qual Tier fica “{selCard.answer}”?</span>
                    <div className="grid gap-2" style={{ gridTemplateColumns: `repeat(${boardTiers.length}, minmax(0, 1fr))` }}>
                      {boardTiers.map((t) => {
                        const letter = TIERS[t]
                        const full = tiers[t].length >= cap
                        return (
                          <button
                            key={letter}
                            type="button"
                            disabled={full || busy}
                            onClick={() => place(t)}
                            aria-label={`Colocar no Tier ${letter}${full ? ' (cheio)' : ''}`}
                            className="btn flex min-h-[58px] flex-col items-center justify-center gap-0.5 p-1 text-2xl leading-none md:min-h-[68px] md:text-[30px]"
                            style={{ background: full ? '#E4DED3' : TIER_COLORS[t] }}
                          >
                            {letter}
                            {full && <span className="font-sans text-[11px] font-black">cheio</span>}
                          </button>
                        )
                      })}
                    </div>
                    <button type="button" className="btn-ghost text-sm" onClick={() => setSel(null)}>
                      Escolher outra resposta
                    </button>
                  </>
                ) : (
                  <>
                    <span className="text-[15px] font-black">
                      {myTurn ? `Escolha uma resposta (${unplaced.length} sem Tier)` : `${nameOf(s, cur)} está jogando · ${unplaced.length} sem Tier`}
                    </span>
                    <div className="grid grid-cols-3 gap-2 md:grid-cols-2">
                      {unplaced.map((c) => {
                        const own = c.author_id === s.me
                        const can = myTurn && !own && !busy
                        return (
                          <button
                            key={c.id}
                            type="button"
                            disabled={!can}
                            onClick={() => setSel(c.id)}
                            className={`min-h-[46px] min-w-0 flex-col justify-center gap-0.5 rounded-xl border-[3px] border-ink px-1.5 py-1 text-left text-ink md:min-h-[60px] md:px-3 md:py-2 ${
                              own ? 'hidden border-dashed bg-lilac md:flex' : 'flex bg-white'
                            } ${can ? 'cursor-pointer' : 'cursor-default'}`}
                            style={{ boxShadow: '3px 3px 0 #1A1033' }}
                          >
                            <span className="clamp-2 text-[13px] font-black leading-tight md:text-[15px]">{c.answer}</span>
                            <span className="hidden text-xs font-extrabold opacity-75 md:block">{own ? 'Sua resposta' : 'Tier ?'}</span>
                          </button>
                        )
                      })}
                    </div>
                    {unplaced.some((c) => c.author_id === s.me) && (
                      <span className="text-xs font-extrabold text-muted md:hidden">
                        + {plural(unplaced.filter((c) => c.author_id === s.me).length, 'resposta sua esperando', 'respostas suas esperando')} os outros
                      </span>
                    )}
                    {skipBtn}
                  </>
                ))}

              {status === 'adjust' &&
                (myTurn ? (
                  <>
                    <span className="text-[15px] font-black">
                      {selCard ? `“${selCard.answer}” está no Tier ${TIERS[selCard.placed_tier ?? 0]}` : 'Toque numa resposta do quadro'}
                    </span>
                    {!pending ? (
                      <>
                        <div className="grid grid-cols-2 gap-2.5">
                          <button type="button" className="btn bg-white" disabled={!canMove(-1) || busy} onClick={() => move(-1)}>
                            Subir 1
                          </button>
                          <button type="button" className="btn bg-white" disabled={!canMove(1) || busy} onClick={() => move(1)}>
                            Descer 1
                          </button>
                        </div>
                        <button type="button" className="btn bg-lilac text-[15px]" disabled={busy} onClick={() => act(() => api.adjustPass(room.id))}>
                          Passar a vez
                        </button>
                      </>
                    ) : (
                      <>
                        <span className="text-[13px] font-extrabold">
                          O Tier {TIERS[pending.to]} está cheio. Trocar “{selCard?.answer}” com qual?
                        </span>
                        {tiers[pending.to].filter((o) => o.author_id !== s.me).map((o) => (
                          <button
                            key={o.id}
                            type="button"
                            disabled={busy}
                            className="pop min-h-11 rounded-[14px] bg-white px-3 py-2 text-left text-sm font-black text-ink"
                            style={{ boxShadow: '3px 3px 0 #1A1033' }}
                            onClick={() => act(() => api.adjustMove(room.id, pending.card, pending.dir, o.id))}
                          >
                            Trocar com “{o.answer}”
                          </button>
                        ))}
                        <button type="button" className="btn-ghost text-sm" onClick={() => setPending(null)}>
                          Cancelar
                        </button>
                      </>
                    )}
                  </>
                ) : (
                  <>
                    <span className="text-[15px] font-black">Vez de {nameOf(s, cur)}</span>
                    <span className="text-sm font-bold text-muted">Cada jogador pode subir ou descer uma resposta em 1 nível, ou passar.</span>
                    {skipBtn}
                  </>
                ))}

              {status === 'reveal' &&
                (!scored ? (
                  <>
                    <span className="text-[15px] font-black">
                      Reveladas: {room.revealed} de {total}
                    </span>
                    {s.is_host ? (
                      <div className="grid grid-cols-2 gap-2.5">
                        <button type="button" className="btn bg-sun text-[15px]" disabled={busy} onClick={() => act(() => api.revealNext(room.id, false))}>
                          Revelar próxima
                        </button>
                        <button type="button" className="btn bg-white text-[15px]" disabled={busy} onClick={() => act(() => api.revealNext(room.id, true))}>
                          Revelar tudo
                        </button>
                      </div>
                    ) : (
                      <span className="text-sm font-extrabold text-muted">{hostName(s)} está revelando as respostas...</span>
                    )}
                  </>
                ) : (
                  <>
                    <Result all={all} correct={correct} n={total} />
                    <span className="text-[13px] font-extrabold text-muted">Veja quem errou em Resultado e os pontos em Ranking.</span>
                    {s.is_host ? (
                      <button type="button" className="btn bg-sun text-[17px]" disabled={busy} onClick={() => act(() => api.nextRound(room.id))}>
                        Próxima rodada
                      </button>
                    ) : (
                      <Waiting>Aguardando {hostName(s)} começar a próxima rodada...</Waiting>
                    )}
                  </>
                ))}
            </>
          )}

          {tab === 'resultado' &&
            (scored ? (
              <>
                <Result all={all} correct={correct} n={total} />
                {s.players.some((p) => p.last_bad_place + p.last_bad_move > 0) ? (
                  <>
                    <span className="text-sm font-black">Quem errou nesta rodada</span>
                    <ul className="m-0 grid list-none grid-cols-2 gap-1.5 p-0 md:grid-cols-1">
                      {s.players
                        .filter((p) => p.last_bad_place + p.last_bad_move > 0)
                        .map((p) => {
                          const parts = []
                          if (p.last_bad_place) parts.push(plural(p.last_bad_place, 'posição errada', 'posições erradas'))
                          if (p.last_bad_move) parts.push(plural(p.last_bad_move, 'movimento errado', 'movimentos errados'))
                          return (
                            <li key={p.id} className="flex min-w-0 items-center gap-2 rounded-xl border-2 border-ink bg-white px-2 py-1.5">
                              <Avatar name={p.name} color={p.color} size={30} src={avatarUrl(p.avatar)} />
                              <div className="flex min-w-0 flex-col">
                                <span className="truncate text-sm font-black">{p.id === s.me ? 'Você' : p.name}</span>
                                <span className="text-xs font-bold text-muted">{parts.join(', ')}</span>
                              </div>
                            </li>
                          )
                        })}
                    </ul>
                  </>
                ) : (
                  <span className="text-[15px] font-extrabold">Ninguém errou nesta rodada!</span>
                )}
              </>
            ) : (
              <>
                <span className="text-[15px] font-black">Rodada {room.round} em andamento</span>
                <span className="text-sm font-bold text-muted">O resultado aparece aqui quando todas as respostas forem reveladas.</span>
              </>
            ))}

          {tab === 'ranking' && (
            <>
              <div className="flex flex-wrap items-baseline justify-between gap-2">
                <span className="text-sm font-black">{plural(room.gabaritos, 'gabarito', 'gabaritos')} do time</span>
                <span className="text-xs font-extrabold text-muted">Acerto +1 · Erro −1 · Gabarito +2</span>
              </div>
              <div className="md:hidden">
                <Ranking s={s} compact showDelta={scored} />
              </div>
              <div className="hidden md:block">
                <Ranking s={s} compact={false} showDelta={scored} />
              </div>
            </>
          )}

          {tab === 'historico' && (
            <ul className="m-0 flex list-none flex-col p-0">
              {s.events.map((e) => (
                <li key={e.id} className="border-b-2 border-dashed border-ink/15 py-1.5 text-sm font-bold">
                  {e.text}
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
    </section>
  )
}

function Result({ all, correct, n }: { all: boolean; correct: number; n: number }) {
  const close = correct >= n - 2
  return (
    <div className={`pop flex flex-none flex-col gap-0.5 rounded-2xl px-3 py-2 md:p-3.5 ${all ? 'bg-mint' : close ? 'bg-sun' : 'bg-coral'}`}>
      <span className="font-display text-xl leading-none md:text-[28px]">{all ? 'GABARITARAM!' : close ? 'Quase lá!' : 'Deu ruim!'}</span>
      <span className="text-sm font-extrabold">{all ? `Todas as ${n} no Tier certo. +2 pra todo mundo!` : `${correct} de ${n} respostas no Tier certo.`}</span>
    </div>
  )
}
