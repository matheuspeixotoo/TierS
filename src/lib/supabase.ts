import { createClient, type User } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

export const isConfigured = Boolean(url && key && !url.includes('SEU-PROJETO'))

export const supabase = createClient(url ?? 'http://localhost:54321', key ?? 'missing-key', {
  auth: { persistSession: true, autoRefreshToken: true, storageKey: 'tiers-auth' },
})

/** Garante um login anônimo: cada aparelho vira um jogador, sem cadastro. */
export async function ensureSession(): Promise<User> {
  const { data } = await supabase.auth.getSession()
  if (data.session) return data.session.user
  const { data: signed, error } = await supabase.auth.signInAnonymously()
  if (error || !signed.user) {
    throw new Error(
      error?.message?.toLowerCase().includes('anonymous')
        ? 'Ative o login anônimo no Supabase (Authentication > Sign In / Providers > Anonymous).'
        : (error?.message ?? 'Não foi possível entrar'),
    )
  }
  return signed.user
}

export function isAnonymous(user: User | null | undefined): boolean {
  return !user || Boolean(user.is_anonymous)
}

/** Mensagens de erro do Auth em português. */
function authMessage(message: string): string {
  const m = message.toLowerCase()
  if (m.includes('invalid login credentials')) return 'E-mail ou senha incorretos.'
  if (m.includes('already registered') || m.includes('already been registered')) return 'Já existe uma conta com esse e-mail.'
  if (m.includes('password should be at least')) return 'A senha precisa ter pelo menos 6 caracteres.'
  if (m.includes('unable to validate email') || m.includes('invalid email')) return 'Digite um e-mail válido.'
  if (m.includes('rate limit') || m.includes('too many')) return 'Muitas tentativas. Espere um pouco e tente de novo.'
  if (m.includes('failed to fetch')) return 'Sem conexão. Confira sua internet.'
  return message
}

/** Cria uma conta com e-mail e senha e já entra nela (sem confirmação por e-mail). */
export async function signUp(email: string, password: string): Promise<User> {
  const { data, error } = await supabase.auth.signUp({ email: email.trim(), password })
  if (error) throw new Error(authMessage(error.message))
  if (!data.session || !data.user) throw new Error('Conta criada, mas o login não foi concluído. Tente entrar.')
  return data.user
}

export async function signIn(email: string, password: string): Promise<User> {
  const { data, error } = await supabase.auth.signInWithPassword({ email: email.trim(), password })
  if (error) throw new Error(authMessage(error.message))
  return data.user
}

/** Sai da conta e volta a ser visitante (novo login anônimo). */
export async function signOut(): Promise<User> {
  await supabase.auth.signOut()
  return ensureSession()
}

/** URL pública de uma foto de perfil guardada no bucket "avatars". */
export function avatarUrl(path: string | null | undefined): string | undefined {
  if (!path) return undefined
  return supabase.storage.from('avatars').getPublicUrl(path).data.publicUrl
}

/** Reduz a imagem para um quadrado pequeno (JPEG) antes de enviar. */
export async function shrinkImage(file: File, size = 256): Promise<Blob> {
  const bitmap = await createImageBitmap(file)
  const side = Math.min(bitmap.width, bitmap.height)
  const canvas = document.createElement('canvas')
  canvas.width = size
  canvas.height = size
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('Não foi possível processar a imagem')
  ctx.drawImage(bitmap, (bitmap.width - side) / 2, (bitmap.height - side) / 2, side, side, 0, 0, size, size)
  bitmap.close()
  return new Promise((resolve, reject) => {
    canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('Não foi possível processar a imagem'))), 'image/jpeg', 0.85)
  })
}

/** Envia a foto para a pasta do usuário e devolve o caminho no bucket. */
export async function uploadAvatar(userId: string, file: File): Promise<string> {
  const blob = await shrinkImage(file)
  const path = `${userId}/avatar-${Date.now()}.jpg`
  const { error } = await supabase.storage.from('avatars').upload(path, blob, { contentType: 'image/jpeg', upsert: false })
  if (error) throw new Error(error.message.includes('Failed to fetch') ? 'Sem conexão. Confira sua internet.' : 'Não foi possível enviar a foto.')
  return path
}

export async function removeAvatarFile(path: string | null | undefined) {
  if (!path) return
  await supabase.storage.from('avatars').remove([path])
}
