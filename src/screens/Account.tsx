import { useState, type FormEvent } from 'react'
import { BigCard, Logo } from '../components/ui'
import { api } from '../lib/api'
import { signIn, signUp } from '../lib/supabase'
import type { Profile } from '../lib/types'

type Mode = 'login' | 'signup' | 'complete'

/**
 * Entrar ou criar conta. Em `complete`, a conta já existe mas ainda não tem
 * perfil (o cadastro parou no meio): só pedimos nome, sobrenome e nick.
 */
export function Account({ mode: initial, onDone, onBack }: { mode: Mode; onDone: (p: Profile) => void; onBack: () => void }) {
  const [mode, setMode] = useState<Mode>(initial)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [first, setFirst] = useState('')
  const [last, setLast] = useState('')
  const [nick, setNick] = useState(() => localStorage.getItem('tiers.name') ?? '')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function submit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    setBusy(true)
    try {
      if (mode === 'login') {
        await signIn(email, password)
        const p = await api.getProfile()
        if (!p) {
          setMode('complete')
          return
        }
        onDone(p)
        return
      }
      if (mode === 'signup') {
        if (!first.trim() || !last.trim() || !nick.trim()) throw new Error('Preencha nome, sobrenome e nick.')
        if (password.length < 6) throw new Error('A senha precisa ter pelo menos 6 caracteres.')
        await signUp(email, password)
      }
      try {
        const p = await api.saveProfile(nick, first, last)
        onDone(p)
      } catch (err) {
        // Conta criada, perfil não: deixa a pessoa corrigir sem recriar a conta.
        setMode('complete')
        throw err
      }
    } catch (err) {
      setError((err as Error).message)
    } finally {
      setBusy(false)
    }
  }

  const title = mode === 'login' ? 'Entrar' : mode === 'signup' ? 'Criar conta' : 'Complete seu perfil'

  return (
    <section className="flex min-h-0 flex-1 items-center justify-center">
      <BigCard className="flex max-w-[520px] flex-col gap-4">
        <div className="flex items-center justify-between gap-3">
          <div className="w-fit rounded-2xl bg-grape px-4 py-3">
            <Logo />
          </div>
          {mode !== 'complete' && (
            <div className="flex rounded-xl border-2 border-ink bg-white p-0.5" role="tablist">
              {(['login', 'signup'] as const).map((m) => (
                <button
                  key={m}
                  type="button"
                  role="tab"
                  aria-selected={mode === m}
                  className={`rounded-[9px] px-3 py-1.5 text-sm font-black ${mode === m ? 'bg-sun' : 'text-muted'}`}
                  onClick={() => {
                    setMode(m)
                    setError(null)
                  }}
                >
                  {m === 'login' ? 'Entrar' : 'Criar conta'}
                </button>
              ))}
            </div>
          )}
        </div>

        <h1 className="m-0 font-display text-[28px] leading-none md:text-4xl">{title}</h1>
        <p className="m-0 text-[15px] font-bold text-muted">
          {mode === 'login'
            ? 'Com a conta, suas partidas ficam no histórico e você entra no ranking geral.'
            : mode === 'signup'
              ? 'Leva 10 segundos. Nome e sobrenome só aparecem pra você; o nick é o que a galera vê.'
              : 'Sua conta existe, mas falta o perfil. Preencha pra concluir.'}
        </p>

        <form className="flex flex-col gap-3" onSubmit={(e) => void submit(e)}>
          {mode !== 'complete' && (
            <>
              <Field id="email" label="E-mail" type="email" value={email} onChange={setEmail} autoComplete="email" placeholder="voce@exemplo.com" />
              <Field
                id="password"
                label="Senha"
                type="password"
                value={password}
                onChange={setPassword}
                autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
                placeholder={mode === 'login' ? 'Sua senha' : 'Pelo menos 6 caracteres'}
              />
            </>
          )}
          {mode !== 'login' && (
            <>
              <div className="grid grid-cols-2 gap-2.5">
                <Field id="first" label="Nome" value={first} onChange={setFirst} autoComplete="given-name" maxLength={40} />
                <Field id="last" label="Sobrenome" value={last} onChange={setLast} autoComplete="family-name" maxLength={40} />
              </div>
              <Field id="nick" label="Nick (como a galera te vê)" value={nick} onChange={setNick} autoComplete="nickname" maxLength={16} placeholder="Até 16 letras" />
            </>
          )}

          {error && (
            <p role="alert" className="m-0 rounded-xl border-2 border-ink bg-coral/30 px-3 py-2 text-[15px] font-extrabold">
              {error}
            </p>
          )}

          <button type="submit" className="btn bg-sun text-xl" disabled={busy}>
            {busy ? '...' : mode === 'login' ? 'Entrar' : mode === 'signup' ? 'Criar conta' : 'Salvar perfil'}
          </button>
          <button type="button" className="btn-ghost self-start text-sm" disabled={busy} onClick={onBack}>
            {mode === 'complete' ? 'Deixar pra depois' : 'Voltar'}
          </button>
        </form>
      </BigCard>
    </section>
  )
}

export function Field({
  id,
  label,
  value,
  onChange,
  type = 'text',
  autoComplete,
  placeholder,
  maxLength,
}: {
  id: string
  label: string
  value: string
  onChange: (v: string) => void
  type?: string
  autoComplete?: string
  placeholder?: string
  maxLength?: number
}) {
  return (
    <div className="flex min-w-0 flex-col gap-1.5">
      <label htmlFor={id} className="text-[15px] font-black">
        {label}
      </label>
      <input
        id={id}
        className="field"
        type={type}
        value={value}
        autoComplete={autoComplete}
        placeholder={placeholder}
        maxLength={maxLength}
        required
        onChange={(e) => onChange(e.target.value)}
      />
    </div>
  )
}
