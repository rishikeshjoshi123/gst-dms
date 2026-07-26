'use client'

import { useTheme } from 'next-themes'
import { useEffect, useState } from 'react'
import { Sun, Moon } from 'lucide-react'

function playSoothingBellSound(switchingToDark: boolean) {
  try {
    const AudioCtx = window.AudioContext || (window as any).webkitAudioContext
    if (!AudioCtx) return
    const ctx = new AudioCtx()

    const now = ctx.currentTime

    // Main fundamental sine wave (pure bell tone)
    const osc1 = ctx.createOscillator()
    // Sub harmonic overtone (adds warmth)
    const osc2 = ctx.createOscillator()

    const gain1 = ctx.createGain()
    const gain2 = ctx.createGain()

    osc1.type = 'sine'
    osc2.type = 'sine'

    // Tuning: Switching to Dark = E5 -> A5 (gentle ascending night chime); Switching to Light = A5 -> E5 (gentle dawn chime)
    const fundamentalFreq = switchingToDark ? 659.25 : 880
    const overtoneFreq = fundamentalFreq * 2.005 // Subtle harmonic shimmer

    osc1.frequency.setValueAtTime(fundamentalFreq, now)
    osc1.frequency.exponentialRampToValueAtTime(switchingToDark ? 880 : 659.25, now + 0.12)

    osc2.frequency.setValueAtTime(overtoneFreq, now)

    // Soft bell envelope: fast smooth attack, long natural exponential decay
    gain1.gain.setValueAtTime(0.0001, now)
    gain1.gain.linearRampToValueAtTime(0.12, now + 0.015)
    gain1.gain.exponentialRampToValueAtTime(0.0001, now + 0.9)

    gain2.gain.setValueAtTime(0.0001, now)
    gain2.gain.linearRampToValueAtTime(0.04, now + 0.01)
    gain2.gain.exponentialRampToValueAtTime(0.0001, now + 0.5)

    osc1.connect(gain1)
    osc2.connect(gain2)

    gain1.connect(ctx.destination)
    gain2.connect(ctx.destination)

    osc1.start(now)
    osc2.start(now)

    osc1.stop(now + 1.0)
    osc2.stop(now + 0.6)
  } catch {
    // Ignore audio context autoplay restrictions gracefully
  }
}

export function ThemeToggle() {
  const { theme, setTheme, resolvedTheme } = useTheme()
  const [mounted, setMounted] = useState(false)

  useEffect(() => setMounted(true), [])

  if (!mounted) {
    return <div className="w-[48px] h-[26px] rounded-full bg-[var(--bg)] border border-[var(--border)] shrink-0" />
  }

  const isDark = resolvedTheme === 'dark' || theme === 'dark'

  const toggleTheme = () => {
    const switchingToDark = !isDark
    playSoothingBellSound(switchingToDark)
    setTheme(switchingToDark ? 'dark' : 'light')
  }

  return (
    <button
      onClick={toggleTheme}
      type="button"
      aria-label={isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode'}
      title={isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode'}
      className="group relative inline-flex h-[26px] w-[48px] shrink-0 cursor-pointer rounded-full border border-[var(--border)] bg-[var(--bg)] p-[2px] transition-colors duration-200 focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--primary)] shadow-xs"
    >
      {/* Track Icons */}
      <div className="absolute inset-0 flex items-center justify-between px-1.5 pointer-events-none z-10">
        <Sun
          size={11}
          className={`transition-opacity duration-200 ${
            isDark ? 'opacity-40 text-[var(--text-muted)]' : 'opacity-0'
          }`}
        />
        <Moon
          size={11}
          className={`transition-opacity duration-200 ${
            isDark ? 'opacity-0' : 'opacity-40 text-[var(--text-muted)]'
          }`}
        />
      </div>

      {/* Sliding Knob */}
      <span
        className={`relative z-20 flex h-[20px] w-[20px] transform items-center justify-center rounded-full bg-[var(--surface)] shadow-xs border border-[var(--border)] transition-transform duration-300 ease-[cubic-bezier(0.34,1.56,0.64,1)] group-hover:scale-105 group-active:scale-95 ${
          isDark ? 'translate-x-[22px]' : 'translate-x-0'
        }`}
      >
        {isDark ? (
          <Moon size={11} className="text-indigo-400 fill-indigo-400/20 transition-transform duration-300 rotate-0" />
        ) : (
          <Sun size={11} className="text-amber-500 fill-amber-500/20 transition-transform duration-300 rotate-0" />
        )}
      </span>
    </button>
  )
}
