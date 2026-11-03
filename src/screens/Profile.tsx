import { useEffect, useRef, useState } from 'react'
import { Avatar, BigCard, Modal } from '../components/ui'
import { api } from '../lib/api'
import { plural } from '../lib/game'
import { avatarUrl, removeAvatarFile, uploadAvatar } from '../lib/supabase'
import type { Profile, RankingRow } from '../lib/types'
import { Field } from './Account'

const MEDAL = ['#FFD93D', '#E4DED3', '#F4A261']

export function ProfileScreen({
  profile,
  email,
  onChange,
  onBack,
  onLogout,
  onToast,
}: {
  profile: Profile
  email: string | null
  onChange: (p: Profile) => void
  onBack: () => void
  onLogout: () => Promise<void>
  onToast: (msg: string) => void
}) {
  const [tab, setTab] = useState<'history' | 'ranking'>('history')
  const [ranking, setRanking] = useState<RankingRow[] | null>(null)
  const [editing, setEditing] = useState(false)
  const [confirmOut, setConfirmOut] = useState(false)
  const [busy, setBusy] = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)
  const st = profile.stats

  useEffect(() => {
    if (tab !== 'ranking' || ranking) return
    api
      .getRanking(50)
      .then(setRanking)
      .catch((e: Error) => onToast(e.message))
  }, [tab, ranking, onToast])

  async function changePhoto(file: File | undefined) {
    if (!file) return
    setBusy(true)
    try {
      const old = profile.avatar_path
      const path = await uploadAvatar(profile.user_id, file)
      await api.setAvatar(path)
      void removeAvatarFile(old)
      onChange({ ...profile, avatar_path: path })
      onToast('Foto atualizada!')
    } catch (e) {
      onToast((e as Error).message)
    } finally {
      setBusy(false)
      if (fileRef.current) fileRef.current.value = ''
    }
  }

  async function removePhoto() {
    setBusy(true)
    try {
      await api.setAvatar(null)
      void removeAvatarFile(profile.avatar_path)
      onChange({ ...profile, avatar_path: null })
    } catch (e) {
      onToast((e as Error).message)
    } finally {
      setBusy(false)
    }
  }

  const photo = avatarUrl(profile.avatar_path)

  return (
    <section className="flex min-h-0 flex-1 items-center justify-center">
      <BigCard className="grid max-w-[1080px] gap-4 md:grid-cols-[minmax(0,5fr)_minmax(0,6fr)] md:gap-8">
        {/* ---------- quem sou ---------- */}
        <div className="flex min-w-0 flex-col gap-3.5">
          <div className="flex items-center gap-3.5">
            <button
              type="button"
              className="relative flex-none rounded-full"
              title="Trocar foto"
              disabled={busy}
              onClick={() => fileRef.current?.click()}
            >
              <Avatar name={profile.nick} color="#FFD93D" size={88} src={photo} />
              <span className="pop absolute -bottom-1 -right-1 flex h-8 w-8 items-center justify-center rounded-full bg-sky text-base" aria-hidden>
                📷
              </span>
            </button>
            <input
              ref={fileRef}
              type="file"
              accept="image/*"
              className="hidden"
              onChange={(e) => void changePhoto(e.target.files?.[0])}
            />
            <div className="flex min-w-0 flex-col">
              <span className="truncate font-display text-[28px] leading-none md:text-4xl">{profile.nick}</span>
              <span className="truncate text-[15px] font-extrabold">
                {profile.first_name} {profile.last_name}
              </span>
              {email && <span className="truncate text-[13px] font-bold text-muted">{email}</span>}
              {profile.rank ? (
                <span className="mt-1 w-fit rounded-full border-2 border-ink bg-sun px-2 py-px text-xs font-black">#{profile.rank} no ranking geral</span>
              ) : (
                <span className="mt-1 text-xs font-bold text-muted">Encerre uma partida pra entrar no ranking</span>
              )}
            </div>
          </div>

          <div className="grid grid-cols-3 gap-2">
            <Stat label="Partidas" value={st.matches} bg="#E9E1FF" />
            <Stat label="Vitórias" value={st.wins} bg="#FFD93D" />
            <Stat label="Pontos" value={st.points} bg="#6BCB77" />
            <Stat label="Acertos" value={st.hits} bg="#4CC9F0" />
            <Stat label="Erros" value={st.misses} bg="#FF6B6B" />
            <Stat label="Gabaritos" value={st.gabaritos} bg="#FFA94D" />
          </div>

          <div className="flex flex-wrap gap-2">
            <button type="button" className="btn bg-white text-[15px]" disabled={busy} onClick={() => setEditing(true)}>
              Editar perfil
            </button>
            {profile.avatar_path && (
              <button type="button" className="btn-ghost text-sm" disabled={busy} onClick={() => void removePhoto()}>
                Tirar foto
              </button>
            )}
            <button type="button" className="btn-ghost text-sm" disabled={busy} onClick={() => setConfirmOut(true)}>
              Sair da conta
            </button>
          </div>
          <button type="button" className="btn bg-sun text-lg" onClick={onBack}>
            Voltar pro jogo
          </button>
        </div>

        {/* ---------- histórico e ranking ---------- */}
        <div className="flex min-h-0 min-w-0 flex-col gap-2.5">
          <div className="flex rounded-xl border-2 border-ink bg-white p-0.5" role="tablist">
            {(['history', 'ranking'] as const).map((t) => (
              <button
                key={t}
                type="button"
                role="tab"
                aria-selected={tab === t}
                className={`flex-1 rounded-[9px] px-3 py-1.5 text-sm font-black ${tab === t ? 'bg-sun' : 'text-muted'}`}
                onClick={() => setTab(t)}
              >
                {t === 'history' ? 'Minhas partidas' : 'Ranking geral'}
              </button>
            ))}
          </div>

          <div className="max-h-[48dvh] min-h-0 overflow-y-auto pr-0.5 md:max-h-[60dvh]">
            {tab === 'history' ? (
              profile.history.length === 0 ? (
                <Empty>Nenhuma partida ainda. Quando o host encerrar uma partida, ela aparece aqui.</Empty>
              ) : (
                <ol className="m-0 flex list-none flex-col gap-1.5 p-0">
                  {profile.history.map((m) => (
                    <li key={m.id} className="flex items-center gap-2 rounded-[10px] border-2 border-ink bg-white px-2 py-1.5">
                      <span
                        className="flex h-8 w-8 flex-none items-center justify-center rounded-lg border-2 border-ink font-display text-sm"
                        style={{ background: MEDAL[m.position - 1] ?? '#FFFFFF' }}
                      >
                        {m.position}º
                      </span>
                      <div className="flex min-w-0 flex-1 flex-col">
                        <span className="truncate text-[14px] font-black">
                          {m.position === 1 ? 'Você venceu' : `${m.winner ?? '?'} venceu`} · {plural(m.players_count, 'jogador', 'jogadores')}
                        </span>
                        <span className="truncate text-xs font-bold text-muted">
                          {formatDate(m.ended_at)} · {plural(m.rounds_done, 'rodada', 'rodadas')} · {m.hits} acertos, {m.misses} erros
                        </span>
                      </div>
                      <span className="flex-none font-display text-[15px]">{m.score} pts</span>
                    </li>
                  ))}
                </ol>
              )
            ) : ranking === null ? (
              <Empty>Carregando...</Empty>
            ) : ranking.length === 0 ? (
              <Empty>Ninguém com conta encerrou uma partida ainda.</Empty>
            ) : (
              <ol className="m-0 flex list-none flex-col gap-1.5 p-0">
                {ranking.map((r, i) => (
                  <li key={r.user_id} className={`flex items-center gap-2 rounded-[10px] border-2 border-ink px-2 py-1.5 ${r.is_me ? 'bg-lilac' : 'bg-white'}`}>
                    <span
                      className="flex h-7 w-7 flex-none items-center justify-center rounded-lg border-2 border-ink font-display text-xs"
                      style={{ background: MEDAL[i] ?? '#FFFFFF' }}
                    >
                      {i + 1}
                    </span>
                    <Avatar name={r.nick} color="#E4DED3" size={30} src={avatarUrl(r.avatar_path)} />
                    <div className="flex min-w-0 flex-1 flex-col">
                      <span className="truncate text-[14px] font-black">{r.is_me ? `${r.nick} (você)` : r.nick}</span>
                      <span className="truncate text-xs font-bold text-muted">
                        {plural(r.wins, 'vitória', 'vitórias')} em {plural(r.matches, 'partida', 'partidas')} · {r.hits} acertos
                      </span>
                    </div>
                    <span className="flex-none font-display text-[15px]">{r.points} pts</span>
                  </li>
                ))}
              </ol>
            )}
          </div>
        </div>
      </BigCard>

      {editing && (
        <EditProfile
          profile={profile}
          onClose={() => setEditing(false)}
          onSaved={(p) => {
            onChange(p)
            setEditing(false)
            onToast('Perfil salvo!')
          }}
        />
      )}

      {confirmOut && (
        <Modal title="Sair da conta?" onClose={() => setConfirmOut(false)}>
          <span className="text-[15px] font-bold">Você volta a jogar como visitante. Seu histórico continua guardado na conta.</span>
          <div className="grid grid-cols-2 gap-2.5">
            <button
              type="button"
              className="btn bg-coral text-[15px]"
              disabled={busy}
              onClick={async () => {
                setBusy(true)
                try {
                  await onLogout()
                } finally {
                  setBusy(false)
                  setConfirmOut(false)
                }
              }}
            >
              Sair
            </button>
            <button type="button" className="btn bg-white text-[15px]" onClick={() => setConfirmOut(false)}>
              Ficar
            </button>
          </div>
        </Modal>
      )}
    </section>
  )
}

function EditProfile({ profile, onClose, onSaved }: { profile: Profile; onClose: () => void; onSaved: (p: Profile) => void }) {
  const [nick, setNick] = useState(profile.nick)
  const [first, setFirst] = useState(profile.first_name ?? '')
  const [last, setLast] = useState(profile.last_name ?? '')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  return (
    <Modal title="Editar perfil" onClose={onClose}>
      <form
        className="flex flex-col gap-3"
        onSubmit={async (e) => {
          e.preventDefault()
          setBusy(true)
          setError(null)
          try {
            onSaved(await api.saveProfile(nick, first, last))
          } catch (err) {
            setError((err as Error).message)
          } finally {
            setBusy(false)
          }
        }}
      >
        <Field id="e-nick" label="Nick" value={nick} onChange={setNick} maxLength={16} autoComplete="nickname" />
        <div className="grid grid-cols-2 gap-2.5">
          <Field id="e-first" label="Nome" value={first} onChange={setFirst} maxLength={40} autoComplete="given-name" />
          <Field id="e-last" label="Sobrenome" value={last} onChange={setLast} maxLength={40} autoComplete="family-name" />
        </div>
        {error && (
          <p role="alert" className="m-0 rounded-xl border-2 border-ink bg-coral/30 px-3 py-2 text-[15px] font-extrabold">
            {error}
          </p>
        )}
        <div className="grid grid-cols-2 gap-2.5">
          <button type="submit" className="btn bg-sun text-[15px]" disabled={busy}>
            {busy ? '...' : 'Salvar'}
          </button>
          <button type="button" className="btn bg-white text-[15px]" disabled={busy} onClick={onClose}>
            Cancelar
          </button>
        </div>
      </form>
    </Modal>
  )
}

function Stat({ label, value, bg }: { label: string; value: number; bg: string }) {
  return (
    <div className="pop flex flex-col items-center rounded-xl px-2 py-1.5" style={{ background: bg }}>
      <span className="font-display text-[22px] leading-none">{value}</span>
      <span className="text-[11px] font-black tracking-wider">{label.toUpperCase()}</span>
    </div>
  )
}

function Empty({ children }: { children: string }) {
  return <p className="m-0 rounded-xl border-2 border-dashed border-ink bg-lilac px-3 py-3 text-center text-sm font-extrabold">{children}</p>
}

function formatDate(iso: string) {
  const d = new Date(iso)
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' }) + ' ' + d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })
}
