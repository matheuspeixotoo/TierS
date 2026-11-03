import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

export const isConfigured = Boolean(url && key && !url.includes('SEU-PROJETO'))

export const supabase = createClient(url ?? 'http://localhost:54321', key ?? 'missing-key', {
  auth: { persistSession: true, autoRefreshToken: true, storageKey: 'tiers-auth' },
})

/** Garante um login anônimo: cada aparelho vira um jogador, sem cadastro. */
export async function ensureSession(): Promise<string> {
  const { data } = await supabase.auth.getSession()
  if (data.session) return data.session.user.id
  const { data: signed, error } = await supabase.auth.signInAnonymously()
  if (error || !signed.user) {
    throw new Error(
      error?.message?.toLowerCase().includes('anonymous')
        ? 'Ative o login anônimo no Supabase (Authentication > Sign In / Providers > Anonymous).'
        : (error?.message ?? 'Não foi possível entrar'),
    )
  }
  return signed.user.id
}
