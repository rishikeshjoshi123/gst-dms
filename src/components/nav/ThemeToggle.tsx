'use client'

import { useTheme } from 'next-themes'
import { useEffect, useState } from 'react'
import { Sun, Moon } from 'lucide-react'

export function ThemeToggle() {
  const { theme, setTheme, resolvedTheme } = useTheme()
  const [mounted, setMounted] = useState(false)

  useEffect(() => setMounted(true), [])

  if (!mounted) {
    return <div className="w-[52px] h-[28px] rounded-full bg-[var(--bg)] border border-[var(--border)] shrink-0" />
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
      className="group relative inline-flex h-[28px] w-[52px] shrink-0 cursor-pointer rounded-full border border-[var(--border)] bg-[var(--bg)] p-[2px] transition-colors duration-300 ease-in-out focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--primary)] shadow-inner"
    >
      {/* Background Icons in track */}
      <div className="absolute inset-0 flex items-center justify-between px-1.5 pointer-events-none text-[10px]">
        <Sun
          size={12}
          className={`transition-opacity duration-300 ${
            isDark ? 'opacity-30 text-[var(--text-muted)]' : 'opacity-0'
          }`}
        />
        <Moon
          size={12}
          className={`transition-opacity duration-300 ${
            isDark ? 'opacity-0' : 'opacity-40 text-[var(--text-muted)]'
          }`}
        />
      </div>

      {/* Sliding Knob */}
      <span
        className={`pointer-events-none flex h-[22px] w-[22px] transform items-center justify-center rounded-full bg-[var(--surface)] shadow-md border border-[var(--border)] transition-transform duration-300 ease-[cubic-bezier(0.34,1.56,0.64,1)] group-hover:scale-105 group-active:scale-95 ${
          isDark ? 'translate-x-[24px]' : 'translate-x-0'
        }`}
      >
        {isDark ? (
          <Moon size={12} className="text-indigo-400 fill-indigo-400/20 transition-transform duration-300 rotate-0" />
        ) : (
          <Sun size={12} className="text-amber-500 fill-amber-500/20 transition-transform duration-300 rotate-0" />
        )}
      </span>
    </button>
  )
}
