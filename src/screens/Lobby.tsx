import { useState } from 'react'
import { PlayerCount } from '../components/PlayerCount'
import { Avatar, BigCard, Waiting } from '../components/ui'
import { avatarUrl } from '../lib/supabase'
import { api } from '../lib/api'
import { HOW_TO, TIER_COLORS, formationText, hostName } from '../lib/game'
import type { GameState, Run } from '../lib/types'

export function Lobby({ s, run, busy, onShare, shareLabel, onLeave }: {
  s: GameState
  run: Run
  busy: boolean
  onShare: () => void
  shareLabel: string
  onLeave: () => void
}) {
  const [howTo, setHowTo] = useState(false)
  const n = s.players.length
  const max = s.room.max_players
  const full = n >= max

  return (
    <section className="flex min-h-0 flex-1 items-center justify-center">
      <BigCard className="grid max-w-[1080px] gap-4 md:grid-cols-2 md:gap-10">
        <div className="flex min-w-0 flex-col gap-3.5">
          <h1 className="m-0 font-display text-[32px] leading-none md:text-6xl">Bora rankear?</h1>
          <p className="m-0 text-base font-bold">Cada um recebe um Tier em segredo. Juntos, vocês tentam montar a Tier List perfeita.</p>
          <ol className={`m-0 list-none flex-col gap-2.5 p-0 ${howTo ? 'flex' : 'hidden md:flex'}`}>
            {HOW_TO.map((t, i) => (
              <li key={t} className="flex items-center gap-3">
                <span
                  className="pop flex h-9 w-9 flex-none items-center justify-center rounded-[10px] font-display text-lg text-ink"
                  style={{ background: TIER_COLORS[i], boxShadow: '3px 3px 0 #1A1033' }}
                >
                  {i + 1}
                </span>
                <span className="text-[15px] font-extrabold">{t}</span>
              </li>
            ))}
            <li className="text-sm font-bold text-muted">Acerto vale +1, erro vale −1. Se o time gabaritar, todo mundo ganha +2.</li>
          </ol>
          <button
            type="button"
            className="self-start rounded-xl border-2 border-ink bg-lilac px-3.5 py-2 text-sm font-black text-ink md:hidden"
            onClick={() => setHowTo((v) => !v)}
          >
            {howTo ? 'Voltar' : 'Como jogar?'}
          </button>
        </div>

        <div className={`min-w-0 flex-col gap-3.5 ${howTo ? 'hidden md:flex' : 'flex'}`}>
          {s.is_host && s.code ? (
            <div className="flex items-center justify-between gap-3 rounded-[18px] bg-ink px-4 py-3 text-cream">
              <div className="flex flex-col gap-0.5">
                <span className="text-xs font-extrabold text-haze">CÓDIGO DA SALA</span>
                <span className="font-display text-3xl tracking-[4px] text-sun">{s.code}</span>
              </div>
              <button type="button" onClick={onShare} className="min-h-11 rounded-xl border-2 border-cream bg-sun px-3.5 py-2 text-sm font-black text-ink">
                {shareLabel}
              </button>
            </div>
          ) : (
            <div className="flex flex-col gap-1 rounded-[18px] bg-ink px-4 py-3 text-cream">
              <span className="text-xs font-extrabold text-haze">VOCÊ ESTÁ NA SALA DE</span>
              <span className="font-display text-[26px] text-sun">{hostName(s)}</span>
              <span className="text-[13px] font-bold">Só o host compartilha o código e começa a partida.</span>
            </div>
          )}

          {s.is_host ? (
            <div className="flex flex-col gap-2">
              <span className="text-[15px] font-black">Tamanho da sala</span>
              <PlayerCount value={max} min={n} disabled={busy} onChange={(v) => void run(() => api.setMaxPlayers(s.room.id, v))} />
            </div>
          ) : (
            <span className="text-[13px] font-extrabold text-muted">{formationText(max)}</span>
          )}
          <span className="text-[15px] font-black">
            Jogadores na sala: {n} de {max}
          </span>
          <ul className="m-0 grid list-none grid-cols-5 gap-2 p-0">
            {s.players.map((p) => {
              const isHost = p.id === s.room.host_player
              return (
                <li key={p.id} className="flex min-w-0 flex-col items-center gap-1">
                  <Avatar name={p.name} color={p.color} size={44} src={avatarUrl(p.avatar)} />
                  <span className="max-w-full truncate text-xs font-extrabold">{p.id === s.me ? 'Você' : p.name}</span>
                  {isHost && <span className="rounded-full bg-ink px-1.5 py-px text-[10px] font-black tracking-wider text-sun">HOST</span>}
                </li>
              )
            })}
          </ul>

          {s.is_host ? (
            <>
              <button type="button" className="btn bg-sun text-xl" disabled={busy || !full} onClick={() => void run(() => api.startGame(s.room.id))}>
                {full ? 'Começar partida' : `Esperando ${max - n} ${max - n === 1 ? 'pessoa' : 'pessoas'}`}
              </button>
            </>
          ) : (
            <Waiting>Aguardando {hostName(s)} começar...</Waiting>
          )}
          <button type="button" className="btn-ghost self-start text-sm" disabled={busy} onClick={onLeave}>
            Sair da sala
          </button>
        </div>
      </BigCard>
    </section>
  )
}
