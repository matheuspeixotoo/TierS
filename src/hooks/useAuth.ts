import { useCallback, useEffect, useState } from 'react'
import type { User } from '@supabase/supabase-js'
import { api } from '../lib/api'
import { ensureSession, isAnonymous, isConfigured, recoveryRequested, supabase } from '../lib/supabase'
import type { Profile } from '../lib/types'

export type AuthStatus = 'loading' | 'ok' | { error: string }

/**
 * Sessão do Supabase (anônima ou conta) e o perfil da conta.
 * `profile` é null para visitante ou enquanto carrega; `profileLoaded`
 * diz se já tentamos buscar o perfil do usuário atual. `recovering` é true
 * quando a pessoa chegou pelo link de "esqueci minha senha".
 */
export function useAuth() {
  const [user, setUser] = useState<User | null>(null)
  const [status, setStatus] = useState<AuthStatus>('loading')
  const [profile, setProfile] = useState<Profile | null>(null)
  const [profileLoaded, setProfileLoaded] = useState(false)
  const [recovering, setRecovering] = useState(recoveryRequested)

  useEffect(() => {
    if (!isConfigured) return
    ensureSession()
      .then((u) => {
        setUser(u)
        setStatus('ok')
      })
      .catch((e: Error) => setStatus({ error: e.message }))
    const { data } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === 'PASSWORD_RECOVERY') setRecovering(true)
      setUser((prev) => (session?.user?.id === prev?.id && session?.user ? prev : (session?.user ?? null)))
    })
    return () => data.subscription.unsubscribe()
  }, [])

  const userId = user?.id ?? null
  const anonymous = isAnonymous(user)

  const refreshProfile = useCallback(async () => {
    if (!userId || anonymous) {
      setProfile(null)
      setProfileLoaded(true)
      return null
    }
    try {
      const p = await api.getProfile()
      setProfile(p)
      return p
    } finally {
      setProfileLoaded(true)
    }
  }, [userId, anonymous])

  useEffect(() => {
    setProfileLoaded(false)
    void refreshProfile().catch(() => setProfileLoaded(true))
  }, [refreshProfile])

  return { user, status, anonymous, profile, profileLoaded, setProfile, refreshProfile, recovering, setRecovering }
}
