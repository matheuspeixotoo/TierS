import { useState } from 'react'
import { PlayerCount } from '../components/PlayerCount'
import { BigCard, Logo } from '../components/ui'
import { api } from '../lib/api'
import { HOW_TO, TIER_COLORS } from '../lib/game'

const NAME_KEY = 'tiers.name'
const SIZE_KEY = 'tiers.size'

export function Home({ initialCode, onEnter }: { initialCode: string; onEnter: (roomId: string) => void }) {
  const [name, setName] = useState(() => localStorage.getItem(NAME_KEY) ?? '')
  const [code, setCode] = useState(initialCode)
  const [size, setSize] = useState(() => Number(localStorage.getItem(SIZE_KEY)) || 4)
  const [busy, setBusy] = useState<'create' | 'join' | null>(null)
  const [error, setError] = useState<string | null>(null)

  const cleanName = name.trim()
  const cleanCode = code.trim().toUpperCase()

  async function go(kind: 'create' | 'join') {
    if (!cleanName) {
      setError('Escolha um apelido primeiro.')
      return
    }
    if (kind === 'join' && cleanCode.length !== 4) {
      setError('O código da sala tem 4 caracteres.')
      return
    }
    setBusy(kind)
    setError(null)
    try {
      localStorage.setItem(NAME_KEY, cleanName)
      if (kind === 'create') localStorage.setItem(SIZE_KEY, String(size))
      const room = kind === 'create' ? await api.createRoom(cleanName, size) : await api.joinRoom(cleanCode, cleanName)
      onEnter(room)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setBusy(null)
    }
  }

  return (
    <section className="flex min-h-0 flex-1 items-center justify-center">
      <BigCard className="grid max-w-[1000px] gap-6 md:grid-cols-2 md:gap-10">
        <div className="flex min-w-0 flex-col gap-4">
          <div className="w-fit rounded-2xl bg-grape px-4 py-3">
            <Logo size="lg" />
          </div>
          <p className="m-0 text-lg font-bold">
            O jogo de Tier List em grupo. Cada um recebe um Tier em segredo e juntos vocês tentam montar a lista perfeita.
          </p>
          <ol className="m-0 hidden list-none flex-col gap-2.5 p-0 md:flex">
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
          </ol>
        </div>

        <form
          className="flex min-w-0 flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault()
            void go(cleanCode.length === 4 ? 'join' : 'create')
          }}
        >
          <div className="flex flex-col gap-2">
            <label htmlFor="nick" className="text-[15px] font-black">
              Seu apelido
            </label>
            <input
              id="nick"
              className="field"
              value={name}
              maxLength={16}
              autoComplete="nickname"
              placeholder="Como a galera te chama?"
              onChange={(e) => setName(e.target.value)}
            />
          </div>

          <div className="flex flex-col gap-2">
            <span className="text-[15px] font-black">Quantas pessoas vão jogar?</span>
            <PlayerCount value={size} onChange={setSize} />
          </div>

          <button type="button" className="btn bg-sun text-xl" disabled={busy !== null} onClick={() => void go('create')}>
            {busy === 'create' ? 'Criando...' : 'Criar sala'}
          </button>

          <div className="flex items-center gap-3 text-sm font-black text-muted">
            <span className="h-0.5 flex-1 bg-ink/15" />
            ou entre numa sala
            <span className="h-0.5 flex-1 bg-ink/15" />
          </div>

          <div className="flex flex-col gap-2">
            <label htmlFor="code" className="text-[15px] font-black">
              Código da sala
            </label>
            <div className="flex gap-2">
              <input
                id="code"
                className="field font-display! tracking-[4px] uppercase"
                value={code}
                maxLength={4}
                autoComplete="off"
                autoCapitalize="characters"
                placeholder="ABCD"
                onChange={(e) => setCode(e.target.value.replace(/[^a-z0-9]/gi, ''))}
              />
              <button type="button" className="btn flex-none bg-sky" disabled={busy !== null} onClick={() => void go('join')}>
                {busy === 'join' ? '...' : 'Entrar'}
              </button>
            </div>
          </div>

          {error && (
            <p role="alert" className="m-0 rounded-xl border-2 border-ink bg-coral/30 px-3 py-2 text-[15px] font-extrabold">
              {error}
            </p>
          )}
        </form>
      </BigCard>
    </section>
  )
}
