import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react'
import { BigCard, Logo, Modal, Toast } from './components/ui'
import { useRoom } from './hooks/useRoom'
import { api } from './lib/api'
import { hostName, nameOf, shareInvite } from './lib/game'
import { ensureSession, isConfigured } from './lib/supabase'
import type { Run, Status } from './lib/types'
import { Deal, Intro } from './screens/Deal'
import { Final } from './screens/Final'
import { Game } from './screens/Game'
import { Home } from './screens/Home'
import { Lobby } from './screens/Lobby'
import { Write } from './screens/Write'

const ROOM_KEY = 'tiers.room'
const INTRO_KEY = 'tiers.intro'

const STEPS: [Status, string][] = [
  ['deal', 'Tema'],
  ['write', 'Responder'],
  ['place', 'Posicionar'],
  ['adjust', 'Ajustar'],
  ['reveal', 'Revelar'],
]

export default function App() {
  const [auth, setAuth] = useState<'loading' | 'ok' | { error: string }>('loading')
  const [roomId, setRoomId] = useState<string | null>(() => localStorage.getItem(ROOM_KEY))
  const [urlCode] = useState(() => (new URLSearchParams(window.location.search).get('sala') ?? '').toUpperCase().slice(0, 4))
  const [busy, setBusy] = useState(false)
  const [toast, setToast] = useState<string | null>(null)
  const [confirmEnd, setConfirmEnd] = useState(false)
  const [shareLabel, setShareLabel] = useState('Compartilhar')
  const [introDone, setIntroDone] = useState(() => sessionStorage.getItem(INTRO_KEY) ?? '')
  const toastTimer = useRef<number | undefined>(undefined)

  useEffect(() => {
    if (!isConfigured) return
    ensureSession()
      .then(() => setAuth('ok'))
      .catch((e: Error) => setAuth({ error: e.message }))
  }, [])

  const { state: s, error, refresh } = useRoom(auth === 'ok' ? roomId : null)

  const showToast = useCallback((msg: string) => {
    setToast(msg)
    window.clearTimeout(toastTimer.current)
    toastTimer.current = window.setTimeout(() => setToast(null), 3500)
  }, [])

  const clearRoom = useCallback(() => {
    localStorage.removeItem(ROOM_KEY)
    setRoomId(null)
  }, [])

  // Sala apagada ou você não está mais nela: volta pra tela inicial.
  useEffect(() => {
    if (roomId && !s && error && /não está nesta sala|não encontrada/i.test(error)) clearRoom()
  }, [roomId, s, error, clearRoom])

  const run: Run = useCallback(
    async (fn) => {
      setBusy(true)
      try {
        await fn()
        await refresh()
        return true
      } catch (e) {
        showToast((e as Error).message)
        await refresh()
        return false
      } finally {
        setBusy(false)
      }
    },
    [refresh, showToast],
  )

  function enter(id: string) {
    localStorage.setItem(ROOM_KEY, id)
    setRoomId(id)
    if (window.location.search) window.history.replaceState(null, '', window.location.pathname)
  }

  async function leave() {
    if (!s) return clearRoom()
    const ok = await run(() => api.leaveRoom(s.room.id))
    if (ok) clearRoom()
  }

  async function share() {
    if (!s?.code) return
    const r = await shareInvite(s.code)
    setShareLabel(r === 'copied' ? 'Copiado!' : r === 'shared' ? 'Enviado!' : `Código: ${s.code}`)
    window.setTimeout(() => setShareLabel('Compartilhar'), 2500)
  }

  const status = s?.room.status
  const inGame = status === 'place' || status === 'adjust' || status === 'reveal'
  const introKey = s ? `${s.room.id}:${s.room.round}` : ''
  const showIntro = s && status === 'write' && introDone !== introKey && s.my_cards.some((c) => !c.answer)
  const stepIdx = STEPS.findIndex(([k]) => k === status)

  let screen: ReactNode
  if (!isConfigured) {
    screen = <SetupNeeded />
  } else if (auth === 'loading' || (roomId && !s && !error)) {
    screen = <Loading />
  } else if (typeof auth === 'object') {
    screen = <Problem text={auth.error} />
  } else if (!s) {
    screen = <Home initialCode={urlCode} onEnter={enter} />
  } else if (status === 'lobby') {
    screen = <Lobby s={s} run={run} busy={busy} onShare={share} shareLabel={shareLabel} onLeave={leave} />
  } else if (status === 'deal') {
    screen = <Deal s={s} run={run} busy={busy} />
  } else if (showIntro) {
    screen = (
      <Intro
        key={introKey}
        s={s}
        chooserName={nameOf(s, s.room.chooser)}
        onDone={() => {
          sessionStorage.setItem(INTRO_KEY, introKey)
          setIntroDone(introKey)
        }}
      />
    )
  } else if (status === 'write') {
    screen = <Write key={introKey} s={s} run={run} busy={busy} />
  } else if (status === 'final') {
    screen = <Final s={s} run={run} busy={busy} onLeave={leave} />
  } else {
    screen = <Game s={s} run={run} busy={busy} />
  }

  return (
    <div className="bg-dots flex h-dvh flex-col overflow-hidden bg-grape p-2.5 text-white md:p-4">
      <div className="mx-auto flex min-h-0 w-full max-w-[1560px] flex-1 flex-col gap-2 md:gap-3">
        <header className="flex flex-none flex-wrap items-center justify-between gap-2.5">
          <Logo />
          {s && stepIdx >= 0 && (
            <nav aria-label="Etapas da rodada" className="hidden gap-2 lg:flex">
              {STEPS.map(([k, label], i) => (
                <span
                  key={k}
                  className={`rounded-full border-2 px-3 py-1.5 text-[13px] font-black ${
                    i === stepIdx ? 'border-ink bg-sun text-ink' : i < stepIdx ? 'border-ink bg-mint text-ink' : 'border-white/25 bg-white/10 text-lilac'
                  }`}
                >
                  {i + 1}. {label}
                </span>
              ))}
            </nav>
          )}
          {s && (
            <div className="flex items-center gap-2">
              {error && <span className="rounded-full bg-coral px-2.5 py-1 text-xs font-black text-ink">Reconectando...</span>}
              {s.is_host && s.code ? (
                <div className="flex min-h-10 items-center gap-2 rounded-full border-[3px] border-ink bg-night py-1 pl-3 pr-1 text-[13px] font-extrabold">
                  <span className="text-haze">SALA</span>
                  <span className="pr-1 font-display tracking-[2px] text-sun">{s.code}</span>
                  {status !== 'lobby' && (
                    <button type="button" onClick={share} className="hidden min-h-8 rounded-full border-2 border-ink bg-sun px-3 text-[13px] font-black text-ink md:block">
                      {shareLabel}
                    </button>
                  )}
                </div>
              ) : (
                <div className="flex min-h-10 items-center gap-2 rounded-full border-[3px] border-ink bg-night px-3.5 text-[13px] font-extrabold">
                  <span className="text-haze">SALA DE</span>
                  <span className="font-display text-sun">{hostName(s)}</span>
                </div>
              )}
              {s.is_host && status !== 'lobby' && status !== 'final' && (
                <button
                  type="button"
                  onClick={() => setConfirmEnd(true)}
                  className="pop min-h-10 rounded-full bg-coral px-3 text-[13px] font-black text-ink"
                  style={{ boxShadow: '3px 3px 0 #1A1033' }}
                >
                  <span className="md:hidden">Encerrar</span>
                  <span className="hidden md:inline">Encerrar partida</span>
                </button>
              )}
            </div>
          )}
        </header>

        {screen}
      </div>

      {confirmEnd && s && (
        <Modal title="Encerrar a partida?" onClose={() => setConfirmEnd(false)}>
          <span className="text-[15px] font-bold">Todo mundo vai para o ranking final com os pontos de agora.</span>
          <div className="grid grid-cols-2 gap-2.5">
            <button
              type="button"
              className="btn bg-coral text-[15px]"
              disabled={busy}
              onClick={async () => {
                await run(() => api.endMatch(s.room.id))
                setConfirmEnd(false)
              }}
            >
              Encerrar
            </button>
            <button type="button" className="btn bg-white text-[15px]" onClick={() => setConfirmEnd(false)}>
              Continuar
            </button>
          </div>
        </Modal>
      )}
      <Toast message={toast} />
      {inGame && <span className="sr-only">Rodada {s?.room.round}</span>}
    </div>
  )
}

function Loading() {
  return (
    <div className="flex flex-1 items-center justify-center" role="status">
      <span className="font-display text-2xl text-cream">Carregando...</span>
    </div>
  )
}

function Problem({ text }: { text: string }) {
  return (
    <section className="flex flex-1 items-center justify-center">
      <BigCard className="flex max-w-[520px] flex-col gap-3">
        <span className="font-display text-2xl">Ops!</span>
        <p className="m-0 text-base font-bold">{text}</p>
        <button type="button" className="btn bg-sun" onClick={() => window.location.reload()}>
          Tentar de novo
        </button>
      </BigCard>
    </section>
  )
}

function SetupNeeded() {
  return (
    <section className="flex flex-1 items-center justify-center">
      <BigCard className="flex max-w-[560px] flex-col gap-3">
        <span className="font-display text-2xl">Falta configurar o Supabase</span>
        <p className="m-0 text-base font-bold">
          Crie o arquivo <code>.env.local</code> na raiz do projeto com <code>VITE_SUPABASE_URL</code> e <code>VITE_SUPABASE_ANON_KEY</code> (veja o
          README) e reinicie o <code>npm run dev</code>.
        </p>
      </BigCard>
    </section>
  )
}
