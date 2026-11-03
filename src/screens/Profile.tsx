import { useEffect, useRef, useState, type FormEvent } from 'react'
import { Avatar, BigCard, Modal } from '../components/ui'
import { api } from '../lib/api'
import { plural } from '../lib/game'
import { avatarUrl, removeAvatarFile, uploadAvatar } from '../lib/supabase'
import type { Friend, Profile, RankingRow } from '../lib/types'
import { ErrorBox, Field } from './Account'

const MEDAL = ['#FFD93D', '#E4DED3', '#F4A261']

type Tab = 'history' | 'ranking' | 'friends'

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
  const [tab, setTab] = useState<Tab>('history')
  const [ranking, setRanking] = useState<RankingRow[] | null>(null)
  const [friends, setFriends] = useState<Friend[] | null>(null)
  const [editing, setEditing] = useState(false)
  const [confirmOut, setConfirmOut] = useState(false)
  const [removing, setRemoving] = useState<Friend | null>(null)
  const [viewing, setViewing] = useState<{ user_id: string; nick: string } | null>(null)
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

  useEffect(() => {
    if (tab !== 'friends' || friends) return
    api
      .getFriends()
      .then(setFriends)
      .catch((e: Error) => onToast(e.message))
  }, [tab, friends, onToast])

  /** Lista de amigos mudou: ranking e contagem precisam acompanhar. */
  function friendsChanged(list: Friend[]) {
    setFriends(list)
    setRanking(null)
    onChange({ ...profile, friends: list.length })
  }

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

  async function removeFriend(f: Friend) {
    setBusy(true)
    try {
      friendsChanged(await api.removeFriend(f.user_id))
      onToast(`${f.nick} saiu da sua lista de amigos.`)
    } catch (e) {
      onToast((e as Error).message)
    } finally {
      setBusy(false)
      setRemoving(null)
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
              {profile.friends === 0 ? (
                <span className="mt-1 text-xs font-bold text-muted">Adicione amigos pra ter um ranking</span>
              ) : profile.rank ? (
                <span className="mt-1 w-fit rounded-full border-2 border-ink bg-sun px-2 py-px text-xs font-black">#{profile.rank} entre os amigos</span>
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

        {/* ---------- histórico, ranking e amigos ---------- */}
        <div className="flex min-h-0 min-w-0 flex-col gap-2.5">
          <div className="flex rounded-xl border-2 border-ink bg-white p-0.5" role="tablist">
            {(['history', 'ranking', 'friends'] as const).map((t) => (
              <button
                key={t}
                type="button"
                role="tab"
                aria-selected={tab === t}
                className={`flex-1 rounded-[9px] px-2 py-1.5 text-sm font-black ${tab === t ? 'bg-sun' : 'text-muted'}`}
                onClick={() => setTab(t)}
              >
                {t === 'history' ? 'Partidas' : t === 'ranking' ? 'Ranking' : `Amigos (${profile.friends})`}
              </button>
            ))}
          </div>

          <div className="max-h-[48dvh] min-h-0 overflow-y-auto pr-0.5 md:max-h-[60dvh]">
            {tab === 'history' ? (
              <History profile={profile} />
            ) : tab === 'ranking' ? (
              <Ranking ranking={ranking} friends={profile.friends} onAddFriends={() => setTab('friends')} onOpen={setViewing} />
            ) : (
              <Friends
                code={profile.friend_code ?? ''}
                friends={friends}
                busy={busy}
                onAdded={friendsChanged}
                onRemove={setRemoving}
                onOpen={setViewing}
                onToast={onToast}
              />
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

      {viewing && <FriendProfile userId={viewing.user_id} nick={viewing.nick} onClose={() => setViewing(null)} />}

      {removing && (
        <Modal title={`Remover ${removing.nick}?`} onClose={() => setRemoving(null)}>
          <span className="text-[15px] font-bold">Vocês saem do ranking um do outro. Dá pra adicionar de novo pelo código.</span>
          <div className="grid grid-cols-2 gap-2.5">
            <button type="button" className="btn bg-coral text-[15px]" disabled={busy} onClick={() => void removeFriend(removing)}>
              Remover
            </button>
            <button type="button" className="btn bg-white text-[15px]" onClick={() => setRemoving(null)}>
              Manter
            </button>
          </div>
        </Modal>
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

function History({ profile }: { profile: Profile }) {
  if (profile.history.length === 0) return <Empty>Nenhuma partida ainda. Quando o host encerrar uma partida, ela aparece aqui.</Empty>
  return (
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
}

function Ranking({
  ranking,
  friends,
  onAddFriends,
  onOpen,
}: {
  ranking: RankingRow[] | null
  friends: number
  onAddFriends: () => void
  onOpen: (f: { user_id: string; nick: string }) => void
}) {
  if (friends === 0) {
    return (
      <div className="flex flex-col gap-2.5">
        <Empty>O ranking é entre você e seus amigos. Adicione alguém pelo código de amigo pra começar a comparar.</Empty>
        <button type="button" className="btn self-start bg-sky text-[15px]" onClick={onAddFriends}>
          Adicionar amigos
        </button>
      </div>
    )
  }
  if (ranking === null) return <Empty>Carregando...</Empty>
  return (
    <ol className="m-0 flex list-none flex-col gap-1.5 p-0">
      {ranking.map((r, i) => (
        <li key={r.user_id}>
          <button
            type="button"
            disabled={r.is_me}
            onClick={() => onOpen({ user_id: r.user_id, nick: r.nick })}
            title={r.is_me ? undefined : `Ver perfil de ${r.nick}`}
            className={`flex w-full items-center gap-2 rounded-[10px] border-2 border-ink px-2 py-1.5 text-left ${r.is_me ? 'bg-lilac' : 'bg-white'}`}
          >
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
                {r.matches === 0
                  ? 'Ainda não encerrou nenhuma partida'
                  : `${plural(r.wins, 'vitória', 'vitórias')} em ${plural(r.matches, 'partida', 'partidas')} · ${r.hits} acertos`}
              </span>
            </div>
            <span className="flex-none font-display text-[15px]">{r.points} pts</span>
          </button>
        </li>
      ))}
    </ol>
  )
}

function Friends({
  code,
  friends,
  busy,
  onAdded,
  onRemove,
  onOpen,
  onToast,
}: {
  code: string
  friends: Friend[] | null
  busy: boolean
  onAdded: (list: Friend[]) => void
  onRemove: (f: Friend) => void
  onOpen: (f: { user_id: string; nick: string }) => void
  onToast: (msg: string) => void
}) {
  const [typed, setTyped] = useState('')
  const [adding, setAdding] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [copied, setCopied] = useState(false)
  const canShare = typeof navigator !== 'undefined' && typeof navigator.share === 'function'

  async function copy() {
    try {
      await navigator.clipboard.writeText(code)
      setCopied(true)
      window.setTimeout(() => setCopied(false), 2000)
    } catch {
      onToast(`Seu código: ${code}`)
    }
  }

  async function share() {
    try {
      await navigator.share({
        title: 'TierS',
        text: `Me adiciona no TierS! Meu código de amigo é ${code}`,
        url: window.location.origin,
      })
    } catch (e) {
      if ((e as Error).name !== 'AbortError') void copy()
    }
  }

  async function add(e: FormEvent) {
    e.preventDefault()
    setError(null)
    setAdding(true)
    try {
      const r = await api.addFriend(typed)
      onAdded(r.friends)
      setTyped('')
      onToast(`${r.added} agora é seu amigo!`)
    } catch (err) {
      setError((err as Error).message)
    } finally {
      setAdding(false)
    }
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="pop flex flex-col gap-2 rounded-2xl bg-ink px-3.5 py-3 text-cream">
        <span className="text-xs font-extrabold tracking-wider text-haze">SEU CÓDIGO DE AMIGO</span>
        <div className="flex flex-wrap items-center justify-between gap-2">
          <span className="font-display text-[30px] leading-none tracking-[4px] text-sun">{code}</span>
          <div className="flex gap-2">
            <button type="button" className="min-h-9 rounded-xl border-2 border-cream bg-sun px-3 text-sm font-black text-ink" onClick={() => void copy()}>
              {copied ? 'Copiado!' : 'Copiar'}
            </button>
            {canShare && (
              <button type="button" className="min-h-9 rounded-xl border-2 border-cream bg-sky px-3 text-sm font-black text-ink" onClick={() => void share()}>
                Enviar
              </button>
            )}
          </div>
        </div>
        <span className="text-xs font-bold text-haze">Quem digitar esse código vira seu amigo, e vocês entram no ranking um do outro.</span>
      </div>

      <form className="flex flex-col gap-2" onSubmit={(e) => void add(e)}>
        <label htmlFor="friend-code" className="text-[15px] font-black">
          Adicionar amigo pelo código
        </label>
        <div className="flex gap-2">
          <input
            id="friend-code"
            className="field font-display! tracking-[4px] uppercase"
            value={typed}
            maxLength={6}
            autoComplete="off"
            autoCapitalize="characters"
            placeholder="ABC123"
            onChange={(e) => setTyped(e.target.value.replace(/[^a-z0-9]/gi, '').toUpperCase())}
          />
          <button type="submit" className="btn flex-none bg-mint text-[15px]" disabled={adding || busy || typed.length !== 6}>
            {adding ? '...' : 'Adicionar'}
          </button>
        </div>
        {error && <ErrorBox>{error}</ErrorBox>}
      </form>

      {friends === null ? (
        <Empty>Carregando...</Empty>
      ) : friends.length === 0 ? (
        <Empty>Você ainda não tem amigos no TierS. Mande seu código pra galera ou digite o de alguém.</Empty>
      ) : (
        <ul className="m-0 flex list-none flex-col gap-1.5 p-0">
          {friends.map((f) => (
            <li key={f.user_id} className="flex items-center gap-2 rounded-[10px] border-2 border-ink bg-white px-2 py-1.5">
              <button type="button" className="flex min-w-0 flex-1 items-center gap-2 text-left" title={`Ver perfil de ${f.nick}`} onClick={() => onOpen(f)}>
                <Avatar name={f.nick} color="#E4DED3" size={30} src={avatarUrl(f.avatar_path)} />
                <div className="flex min-w-0 flex-1 flex-col">
                  <span className="truncate text-[14px] font-black underline decoration-2 underline-offset-2">{f.nick}</span>
                  <span className="truncate text-xs font-bold text-muted">Amigos desde {formatDate(f.since)}</span>
                </div>
              </button>
              <button type="button" className="btn-ghost text-xs" disabled={busy} onClick={() => onRemove(f)}>
                Remover
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

/** Perfil de um amigo: nick, foto, estatísticas, posição entre os amigos dele e últimas partidas. */
function FriendProfile({ userId, nick, onClose }: { userId: string; nick: string; onClose: () => void }) {
  const [p, setP] = useState<Profile | null | undefined>(undefined)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    api
      .getProfile(userId)
      .then(setP)
      .catch((e: Error) => setError(e.message))
  }, [userId])

  return (
    <Modal title={`Perfil de ${nick}`} onClose={onClose}>
      {error ? (
        <ErrorBox>{error}</ErrorBox>
      ) : p === undefined ? (
        <Empty>Carregando...</Empty>
      ) : p === null ? (
        <Empty>Esse perfil não existe mais.</Empty>
      ) : (
        <div className="flex max-h-[70dvh] min-h-0 flex-col gap-3 overflow-y-auto pr-0.5">
          <div className="flex items-center gap-3">
            <Avatar name={p.nick} color="#4CC9F0" size={64} src={avatarUrl(p.avatar_path)} />
            <div className="flex min-w-0 flex-col">
              <span className="truncate font-display text-2xl leading-none">{p.nick}</span>
              <span className="text-xs font-bold text-muted">No TierS desde {formatDate(p.created_at).slice(0, 5)} · {plural(p.friends, 'amigo', 'amigos')}</span>
              {p.rank ? (
                <span className="mt-1 w-fit rounded-full border-2 border-ink bg-sun px-2 py-px text-xs font-black">#{p.rank} entre os amigos dele</span>
              ) : (
                <span className="mt-1 text-xs font-bold text-muted">Ainda não encerrou nenhuma partida</span>
              )}
            </div>
          </div>
          <div className="grid grid-cols-3 gap-2">
            <Stat label="Partidas" value={p.stats.matches} bg="#E9E1FF" />
            <Stat label="Vitórias" value={p.stats.wins} bg="#FFD93D" />
            <Stat label="Pontos" value={p.stats.points} bg="#6BCB77" />
            <Stat label="Acertos" value={p.stats.hits} bg="#4CC9F0" />
            <Stat label="Erros" value={p.stats.misses} bg="#FF6B6B" />
            <Stat label="Gabaritos" value={p.stats.gabaritos} bg="#FFA94D" />
          </div>
          {p.history.length > 0 && (
            <div className="flex flex-col gap-1.5">
              <span className="text-xs font-black tracking-wider text-muted">ÚLTIMAS PARTIDAS</span>
              <ol className="m-0 flex list-none flex-col gap-1.5 p-0">
                {p.history.slice(0, 5).map((m) => (
                  <li key={m.id} className="flex items-center gap-2 rounded-[10px] border-2 border-ink bg-white px-2 py-1">
                    <span
                      className="flex h-7 w-7 flex-none items-center justify-center rounded-lg border-2 border-ink font-display text-xs"
                      style={{ background: MEDAL[m.position - 1] ?? '#FFFFFF' }}
                    >
                      {m.position}º
                    </span>
                    <span className="min-w-0 flex-1 truncate text-xs font-bold text-muted">
                      {formatDate(m.ended_at)} · {plural(m.players_count, 'jogador', 'jogadores')} · {m.hits} acertos, {m.misses} erros
                    </span>
                    <span className="flex-none font-display text-[14px]">{m.score} pts</span>
                  </li>
                ))}
              </ol>
            </div>
          )}
        </div>
      )}
      <button type="button" className="btn bg-white text-[15px]" onClick={onClose}>
        Fechar
      </button>
    </Modal>
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
        {error && <ErrorBox>{error}</ErrorBox>}
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
