import type { CSSProperties, ReactNode } from 'react'
import { TIER_COLORS, TIERS, initials } from '../lib/game'

export function Logo({ size = 'md' }: { size?: 'md' | 'lg' }) {
  const big = size === 'lg'
  return (
    <div className="flex items-center gap-1.5 select-none" aria-label="TierS">
      <span
        className={`font-display leading-none text-cream ${big ? 'text-5xl md:text-6xl' : 'text-2xl md:text-[32px]'}`}
        style={{ textShadow: '3px 3px 0 #1A1033' }}
      >
        TIER
      </span>
      <span
        className={`pop inline-block -rotate-[8deg] rounded-xl bg-coral px-2 py-0.5 font-display leading-none text-ink ${big ? 'text-4xl md:text-5xl' : 'text-xl md:text-[28px]'}`}
        style={{ boxShadow: '3px 3px 0 #1A1033' }}
      >
        S
      </span>
    </div>
  )
}

export function Avatar({
  name,
  color,
  size = 40,
  ring = false,
  label,
  src,
}: {
  name: string
  color: string
  size?: number
  ring?: boolean
  label?: string
  /** Foto de perfil; sem ela mostramos as iniciais sobre a cor do jogador. */
  src?: string
}) {
  return (
    <span
      title={label ?? name}
      className="flex flex-none items-center justify-center overflow-hidden rounded-full border-[3px] border-ink font-black text-ink"
      style={{
        width: size,
        height: size,
        background: color,
        fontSize: Math.round(size * 0.38),
        boxShadow: ring ? '0 0 0 4px #FFD93D' : undefined,
        transform: ring ? 'scale(1.08)' : undefined,
      }}
    >
      {src ? <img src={src} alt="" className="h-full w-full object-cover" draggable={false} /> : initials(name)}
    </span>
  )
}

export function TierBlock({ tier, className = '', style }: { tier: number; className?: string; style?: CSSProperties }) {
  return (
    <div
      className={`pop flex items-center justify-center font-display text-ink ${className}`}
      style={{ background: TIER_COLORS[tier], ...style }}
    >
      {TIERS[tier]}
    </div>
  )
}

/** Cartão creme grande das telas fora do jogo. */
export function BigCard({ children, className = '' }: { children: ReactNode; className?: string }) {
  return (
    <div
      className={`pop-lg box-border max-h-full w-full overflow-y-auto rounded-[22px] bg-cream p-4 text-ink md:rounded-[28px] md:p-8 ${className}`}
    >
      {children}
    </div>
  )
}

export function Waiting({ children }: { children: ReactNode }) {
  return (
    <div className="rounded-2xl border-[3px] border-dashed border-ink bg-lilac p-3.5 text-center font-display text-[15px] text-ink" role="status">
      {children}
    </div>
  )
}

export function Modal({ title, children, onClose }: { title: string; children: ReactNode; onClose: () => void }) {
  return (
    <div
      className="fixed inset-0 z-30 flex items-center justify-center bg-abyss/70 p-4"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose()
      }}
    >
      <div role="dialog" aria-modal="true" aria-label={title} className="pop-lg flex w-full max-w-[420px] flex-col gap-3.5 rounded-3xl bg-cream p-5 text-ink">
        <span className="font-display text-[22px] leading-tight">{title}</span>
        {children}
      </div>
    </div>
  )
}

export function Toast({ message }: { message: string | null }) {
  if (!message) return null
  return (
    <div
      role="alert"
      className="toast pop fixed left-1/2 top-3 z-40 max-w-[92vw] rounded-2xl bg-coral px-4 py-2.5 text-center text-[15px] font-black text-ink"
    >
      {message}
    </div>
  )
}
