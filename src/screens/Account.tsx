import { useState, type FormEvent } from 'react'
import { BigCard, Logo } from '../components/ui'
import { api } from '../lib/api'
import { sendPasswordReset, signIn, signUp, updatePassword } from '../lib/supabase'
import type { Profile } from '../lib/types'

type Mode = 'login' | 'signup' | 'complete' | 'reset' | 'sent'

/**
 * Entrar ou criar conta. Em `complete`, a conta já existe mas ainda não tem
 * perfil (o cadastro parou no meio): só pedimos nome, sobrenome e nick.
 * Em `reset`, pedimos o e-mail para mandar o link de senha nova; `sent` é
 * a confirmação de envio.
 */
export function Account({
  mode: initial,
  onDone,
  onBack,
}: {
  mode: 'login' | 'signup' | 'complete' | 'reset'
  onDone: (p: Profile) => void
  onBack: () => void
}) {
  const [mode, setMode] = useState<Mode>(initial)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [first, setFirst] = useState('')
  const [last, setLast] = useState('')
  const [nick, setNick] = useState(() => localStorage.getItem('tiers.name') ?? '')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  function go(m: Mode) {
    setMode(m)
    setError(null)
  }

  async function submit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    setBusy(true)
    try {
      if (mode === 'reset') {
        await sendPasswordReset(email)
        setMode('sent')
        return
      }
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

  const title =
    mode === 'login'
      ? 'Entrar'
      : mode === 'signup'
        ? 'Criar conta'
        : mode === 'complete'
          ? 'Complete seu perfil'
          : mode === 'reset'
            ? 'Esqueci minha senha'
            : 'E-mail enviado'

  const hint =
    mode === 'login'
      ? 'Com a conta, suas partidas ficam no histórico e você entra no ranking com seus amigos.'
      : mode === 'signup'
        ? 'Leva 10 segundos. Nome e sobrenome só aparecem pra você; o nick é o que a galera vê.'
        : mode === 'complete'
          ? 'Sua conta existe, mas falta o perfil. Preencha pra concluir.'
          : mode === 'reset'
            ? 'Digite o e-mail da sua conta. A gente manda um link pra você criar uma senha nova.'
            : `Se existe uma conta com o e-mail ${email.trim()}, o link pra criar uma senha nova já está a caminho. Confira a caixa de entrada e o spam. O link vale por 1 hora.`

  return (
    <section className="flex min-h-0 flex-1 items-center justify-center">
      <BigCard className="flex max-w-[520px] flex-col gap-4">
        <div className="flex items-center justify-between gap-3">
          <div className="w-fit rounded-2xl bg-grape px-4 py-3">
            <Logo />
          </div>
          {(mode === 'login' || mode === 'signup') && (
            <div className="flex rounded-xl border-2 border-ink bg-white p-0.5" role="tablist">
              {(['login', 'signup'] as const).map((m) => (
                <button
                  key={m}
                  type="button"
                  role="tab"
                  aria-selected={mode === m}
                  className={`rounded-[9px] px-3 py-1.5 text-sm font-black ${mode === m ? 'bg-sun' : 'text-muted'}`}
                  onClick={() => go(m)}
                >
                  {m === 'login' ? 'Entrar' : 'Criar conta'}
                </button>
              ))}
            </div>
          )}
        </div>

        <h1 className="m-0 font-display text-[28px] leading-none md:text-4xl">{title}</h1>
        <p className="m-0 text-[15px] font-bold text-muted">{hint}</p>

        {mode === 'sent' ? (
          <div className="flex flex-col gap-3">
            <button type="button" className="btn bg-sun text-xl" onClick={() => go('login')}>
              Voltar pra entrar
            </button>
            <button type="button" className="btn-ghost self-start text-sm" onClick={() => go('reset')}>
              Não chegou? Enviar de novo
            </button>
          </div>
        ) : (
          <form className="flex flex-col gap-3" onSubmit={(e) => void submit(e)}>
            {mode !== 'complete' && (
              <Field id="email" label="E-mail" type="email" value={email} onChange={setEmail} autoComplete="email" placeholder="voce@exemplo.com" />
            )}
            {(mode === 'login' || mode === 'signup') && (
              <Field
                id="password"
                label="Senha"
                type="password"
                value={password}
                onChange={setPassword}
                autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
                placeholder={mode === 'login' ? 'Sua senha' : 'Pelo menos 6 caracteres'}
              />
            )}
            {mode === 'login' && (
              <button type="button" className="self-start text-sm font-black text-muted underline decoration-2 underline-offset-2" onClick={() => go('reset')}>
                Esqueci minha senha
              </button>
            )}
            {(mode === 'signup' || mode === 'complete') && (
              <>
                <div className="grid grid-cols-2 gap-2.5">
                  <Field id="first" label="Nome" value={first} onChange={setFirst} autoComplete="given-name" maxLength={40} />
                  <Field id="last" label="Sobrenome" value={last} onChange={setLast} autoComplete="family-name" maxLength={40} />
                </div>
                <Field id="nick" label="Nick (como a galera te vê)" value={nick} onChange={setNick} autoComplete="nickname" maxLength={16} placeholder="Até 16 letras" />
              </>
            )}

            {error && <ErrorBox>{error}</ErrorBox>}

            <button type="submit" className="btn bg-sun text-xl" disabled={busy}>
              {busy ? '...' : mode === 'login' ? 'Entrar' : mode === 'signup' ? 'Criar conta' : mode === 'complete' ? 'Salvar perfil' : 'Enviar link'}
            </button>
            <button type="button" className="btn-ghost self-start text-sm" disabled={busy} onClick={mode === 'reset' ? () => go('login') : onBack}>
              {mode === 'complete' ? 'Deixar pra depois' : 'Voltar'}
            </button>
          </form>
        )}
      </BigCard>
    </section>
  )
}

/**
 * Tela aberta pelo link do e-mail de "esqueci minha senha". A sessão já é
 * da conta (o link loga a pessoa); só falta escolher a senha nova.
 */
export function ResetPassword({ expired, onDone, onAskAgain }: { expired: boolean; onDone: () => void; onAskAgain: () => void }) {
  const [password, setPassword] = useState('')
  const [again, setAgain] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function submit(e: FormEvent) {
    e.preventDefault()
    setError(null)
    if (password.length < 6) return setError('A senha precisa ter pelo menos 6 caracteres.')
    if (password !== again) return setError('As duas senhas estão diferentes.')
    setBusy(true)
    try {
      await updatePassword(password)
      onDone()
    } catch (err) {
      setError((err as Error).message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <section className="flex min-h-0 flex-1 items-center justify-center">
      <BigCard className="flex max-w-[520px] flex-col gap-4">
        <div className="w-fit rounded-2xl bg-grape px-4 py-3">
          <Logo />
        </div>
        <h1 className="m-0 font-display text-[28px] leading-none md:text-4xl">{expired ? 'Link expirado' : 'Senha nova'}</h1>
        {expired ? (
          <>
            <p className="m-0 text-[15px] font-bold text-muted">Esse link de senha nova expirou ou já foi usado. Peça outro e abra o e-mail mais recente.</p>
            <button type="button" className="btn bg-sun text-xl" onClick={onAskAgain}>
              Pedir outro link
            </button>
          </>
        ) : (
          <form className="flex flex-col gap-3" onSubmit={(e) => void submit(e)}>
            <p className="m-0 text-[15px] font-bold text-muted">Escolha a senha nova da sua conta. Você já vai entrar com ela.</p>
            <Field id="new-password" label="Senha nova" type="password" value={password} onChange={setPassword} autoComplete="new-password" placeholder="Pelo menos 6 caracteres" />
            <Field id="new-password-2" label="Repita a senha" type="password" value={again} onChange={setAgain} autoComplete="new-password" placeholder="A mesma senha" />
            {error && <ErrorBox>{error}</ErrorBox>}
            <button type="submit" className="btn bg-sun text-xl" disabled={busy}>
              {busy ? '...' : 'Salvar senha'}
            </button>
          </form>
        )}
      </BigCard>
    </section>
  )
}

export function ErrorBox({ children }: { children: string }) {
  return (
    <p role="alert" className="m-0 rounded-xl border-2 border-ink bg-coral/30 px-3 py-2 text-[15px] font-extrabold">
      {children}
    </p>
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
