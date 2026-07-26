'use client'

import { useTheme } from 'next-themes'
import { useEffect, useState } from 'react'
import { Sun, Moon, Sparkles } from 'lucide-react'

export function ThemeToggle() {
  const { theme, setTheme, resolvedTheme } = useTheme()
  const [mounted, setMounted] = useState(false)

  useEffect(() => setMounted(true), [])

  if (!mounted) {
    return <div className="w-[56px] h-[30px] rounded-full bg-[var(--surface)] border border-[var(--border)] shrink-0" />
  }

  const isDark = resolvedTheme === 'dark' || theme === 'dark'

  const toggleTheme = () => {
    setTheme(isDark ? 'light' : 'dark')
  }

  return (
    <button
      onClick={toggleTheme}
      type="button"
      aria-label={isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode'}
      title={isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode'}
      className={`group relative inline-flex h-[30px] w-[56px] shrink-0 cursor-pointer rounded-full border transition-all duration-500 ease-out focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--primary)] p-[3px] shadow-sm ${
        isDark
          ? 'bg-slate-950/80 border-indigo-500/40 shadow-[0_0_15px_rgba(99,102,241,0.25)]'
          : 'bg-amber-50/90 border-amber-400/40 shadow-[0_0_15px_rgba(245,158,11,0.25)]'
      }`}
    >
      {/* Background Track Glow Effect */}
      <div
        className={`absolute inset-0 rounded-full transition-opacity duration-500 pointer-events-none opacity-40 blur-[4px] ${
          isDark
            ? 'bg-gradient-to-r from-indigo-600 via-purple-600 to-cyan-400'
            : 'bg-gradient-to-r from-amber-400 via-orange-400 to-yellow-300'
        }`}
      />

      {/* Track Icons */}
      <div className="absolute inset-0 flex items-center justify-between px-2 pointer-events-none z-10">
        <Sun
          size={13}
          className={`transition-all duration-300 ${
            isDark ? 'opacity-30 text-amber-500/50' : 'opacity-0 scale-75'
          }`}
        />
        <Moon
          size={13}
          className={`transition-all duration-300 ${
            isDark ? 'opacity-0 scale-75' : 'opacity-40 text-indigo-400/50'
          }`}
        />
      </div>

      {/* Sliding Gradient Knob */}
      <span
        className={`relative z-20 flex h-[22px] w-[22px] transform items-center justify-center rounded-full shadow-lg transition-all duration-500 ease-[cubic-bezier(0.34,1.56,0.64,1)] group-hover:scale-110 group-active:scale-95 ${
          isDark
            ? 'translate-x-[26px] bg-gradient-to-br from-indigo-600 via-purple-600 to-cyan-500 text-white shadow-[0_0_12px_rgba(99,102,241,0.8)] border border-indigo-300/40'
            : 'translate-x-0 bg-gradient-to-br from-amber-400 via-orange-400 to-yellow-300 text-amber-950 shadow-[0_0_12px_rgba(245,158,11,0.8)] border border-amber-200/60'
        }`}
      >
        {isDark ? (
          <div className="relative flex items-center justify-center">
            <Moon
              size={12}
              className="text-cyan-100 fill-cyan-200/30 transition-transform duration-500 group-hover:rotate-[20deg]"
            />
            <Sparkles
              size={7}
              className="absolute -top-1 -right-1 text-cyan-200 animate-pulse"
            />
          </div>
        ) : (
          <div className="relative flex items-center justify-center">
            <Sun
              size={13}
              className="text-amber-950 fill-amber-300/40 animate-[spin_10s_linear_infinite] transition-transform duration-500 group-hover:scale-110"
            />
            <span className="absolute inset-0 rounded-full bg-amber-300/40 animate-ping opacity-75" />
          </div>
        )}
      </span>
    </button>
  )
}
