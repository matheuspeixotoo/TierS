import { useCallback, useEffect, useRef, useState } from 'react'
import { api } from '../lib/api'
import { supabase } from '../lib/supabase'
import type { GameState } from '../lib/types'

/**
 * Mantém o estado da sala sincronizado: escuta mudanças na linha da sala
 * (Realtime) e busca o estado completo com get_state. Um polling leve cobre
 * conexões que caem sem avisar.
 */
export function useRoom(roomId: string | null) {
  const [state, setState] = useState<GameState | null>(null)
  const [error, setError] = useState<string | null>(null)
  const latest = useRef<{ room: string | null; version: number }>({ room: null, version: -1 })
  const inflight = useRef(false)
  const again = useRef(false)

  const refresh = useCallback(async () => {
    if (!roomId) return
    if (inflight.current) {
      again.current = true
      return
    }
    inflight.current = true
    try {
      const s = await api.getState(roomId)
      const l = latest.current
      if (l.room !== roomId || s.room.version >= l.version) {
        latest.current = { room: roomId, version: s.room.version }
        setState(s)
      }
      setError(null)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      inflight.current = false
      if (again.current) {
        again.current = false
        void refresh()
      }
    }
  }, [roomId])

  useEffect(() => {
    latest.current = { room: null, version: -1 }
    setState(null)
    setError(null)
    if (!roomId) return
    void refresh()
    const channel = supabase
      .channel(`room-${roomId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'rooms', filter: `id=eq.${roomId}` }, () => void refresh())
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') void refresh()
      })
    const poll = window.setInterval(() => void refresh(), 5000)
    const onVisible = () => {
      if (document.visibilityState === 'visible') void refresh()
    }
    document.addEventListener('visibilitychange', onVisible)
    window.addEventListener('online', onVisible)
    return () => {
      void supabase.removeChannel(channel)
      window.clearInterval(poll)
      document.removeEventListener('visibilitychange', onVisible)
      window.removeEventListener('online', onVisible)
    }
  }, [roomId, refresh])

  return { state, error, refresh }
}
