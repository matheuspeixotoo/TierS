import { BigCard } from '../components/ui'
import { Ranking } from '../components/Ranking'
import { api } from '../lib/api'
import { hostName, plural } from '../lib/game'
import type { GameState, Run } from '../lib/types'

export function Final({ s, run, busy, onLeave }: { s: GameState; run: Run; busy: boolean; onLeave: () => void }) {
  const byHits = [...s.players].sort((a, b) => b.hits - a.hits)[0]
  const byMiss = [...s.players].sort((a, b) => b.misses - a.misses)[0]
  const label = (id: string, name: string) => (id === s.me ? 'Você' : name)

  return (
    <section className="flex min-h-0 flex-1 items-center justify-center">
      <BigCard className="grid max-w-[1080px] gap-4 md:grid-cols-2 md:gap-10">
        <div className="flex min-w-0 flex-col gap-3.5">
          <h1 className="m-0 font-display text-[32px] leading-none md:text-6xl">Fim de partida!</h1>
          <p className="m-0 text-base font-extrabold">
            {plural(s.room.rounds_done, 'rodada jogada', 'rodadas jogadas')} · {plural(s.room.gabaritos, 'gabarito', 'gabaritos')} do time
          </p>
          <div className="grid grid-cols-2 gap-3 md:grid-cols-1">
            <div className="pop flex min-w-0 -rotate-1 flex-col gap-0.5 rounded-2xl bg-mint px-3.5 py-3">
              <span className="text-xs font-black tracking-wider">MAIS ACERTOU</span>
              <span className="truncate font-display text-lg leading-tight md:text-[26px]">
                {byHits && byHits.hits > 0 ? label(byHits.id, byHits.name) : 'Ninguém ainda'}
              </span>
              <span className="text-[13px] font-extrabold">{byHits && byHits.hits > 0 ? plural(byHits.hits, 'acerto', 'acertos') : 'Sem rodadas completas'}</span>
            </div>
            <div className="pop flex min-w-0 rotate-1 flex-col gap-0.5 rounded-2xl bg-coral px-3.5 py-3">
              <span className="text-xs font-black tracking-wider">MAIS ERROU</span>
              <span className="truncate font-display text-lg leading-tight md:text-[26px]">
                {byMiss && byMiss.misses > 0 ? label(byMiss.id, byMiss.name) : 'Ninguém'}
              </span>
              <span className="text-[13px] font-extrabold">{byMiss && byMiss.misses > 0 ? plural(byMiss.misses, 'erro', 'erros') : 'Nenhum erro'}</span>
            </div>
          </div>
        </div>
        <div className="flex min-w-0 flex-col gap-2.5">
          <span className="text-[15px] font-black">Ranking final</span>
          <div className="md:hidden">
            <Ranking s={s} compact showDelta={false} />
          </div>
          <div className="hidden md:block">
            <Ranking s={s} compact={false} showDelta={false} />
          </div>
          {s.is_host ? (
            <button type="button" className="btn bg-sun text-lg" disabled={busy} onClick={() => void run(() => api.newMatch(s.room.id))}>
              Nova partida
            </button>
          ) : (
            <span className="text-sm font-extrabold text-muted">{hostName(s)} encerrou a partida. Se ele abrir uma nova, você volta pra sala.</span>
          )}
          <button type="button" className="btn-ghost self-start text-sm" disabled={busy} onClick={onLeave}>
            Sair da sala
          </button>
        </div>
      </BigCard>
    </section>
  )
}
