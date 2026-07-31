'use client'

import { useTheme } from 'next-themes'
import { useEffect, useState } from 'react'
import { Sun, Moon } from 'lucide-react'

export function ThemeToggle() {
  const { theme, setTheme, resolvedTheme } = useTheme()
  const [mounted, setMounted] = useState(false)

  useEffect(() => setMounted(true), [])

  if (!mounted) {
    return <div className="w-[56px] h-[28px] rounded-full bg-[var(--border)] shrink-0" />
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
      className="group relative inline-flex h-[28px] w-[56px] shrink-0 cursor-pointer rounded-full border border-[var(--border-strong)] bg-[var(--border)] p-[3px] transition-all duration-300 focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--primary)] hover:border-[var(--primary)]/40"
    >
      {/* Track Icons */}
      <div className="absolute inset-0 flex items-center justify-between px-2 pointer-events-none z-10">
        <Sun
          size={13}
          strokeWidth={2.5}
          className={`transition-all duration-300 ${
            isDark ? 'opacity-50 text-amber-400' : 'opacity-0 scale-75'
          }`}
        />
        <Moon
          size={13}
          strokeWidth={2.5}
          className={`transition-all duration-300 ${
            isDark ? 'opacity-0 scale-75' : 'opacity-50 text-indigo-400'
          }`}
        />
      </div>

      {/* Sliding Knob */}
      <span
        className={`relative z-20 flex h-[20px] w-[20px] transform items-center justify-center rounded-full shadow-md transition-all duration-300 ease-[cubic-bezier(0.34,1.56,0.64,1)] group-hover:scale-110 group-active:scale-90 ${
          isDark
            ? 'translate-x-[26px] bg-[#1E293B] border border-indigo-500/30 shadow-indigo-500/20'
            : 'translate-x-0 bg-white border border-amber-400/30 shadow-amber-500/20'
        }`}
      >
        {isDark ? (
          <Moon size={12} strokeWidth={2.5} className="text-indigo-400 transition-transform duration-300" />
        ) : (
          <Sun size={12} strokeWidth={2.5} className="text-amber-500 transition-transform duration-300" />
        )}
      </span>
    </button>
  )
}
