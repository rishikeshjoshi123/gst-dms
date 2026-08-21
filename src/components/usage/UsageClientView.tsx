'use client'

import React, { useState, useMemo } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { PricingManager } from './PricingManager'
import { 
  Calendar as CalendarIcon, 
  ChevronLeft, 
  ChevronRight, 
  X, 
  Search, 
  Filter,
  Layers,
  Sparkles,
  ArrowRight,
  RotateCcw
} from 'lucide-react'

export type UsageLogItem = {
  id: string
  created_at: string
  org_id?: string
  user_id?: string | null
  document_id?: string | null
  operation_type: string
  model_name: string
  input_tokens: number
  output_tokens: number
  total_cost_usd: number
  documents?: { reference_number: string | null } | null
}

export type PricingRow = {
  model_name: string
  input_price_per_1m: number
  output_price_per_1m: number
}

interface UsageClientViewProps {
  logs: UsageLogItem[]
  initialPricing: PricingRow[]
}

// Helper to format date to YYYY-MM-DD in local time
function toYMD(date: Date): string {
  const y = date.getFullYear()
  const m = String(date.getMonth() + 1).padStart(2, '0')
  const d = String(date.getDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

export function UsageClientView({ logs, initialPricing }: UsageClientViewProps) {
  // Filters & State
  const [selectedDate, setSelectedDate] = useState<string | null>(null) // YYYY-MM-DD
  const [viewMode, setViewMode] = useState<'all' | 'calendar'>('all')
  const [calendarMonth, setCalendarMonth] = useState<Date>(() => {
    const d = new Date()
    d.setDate(1)
    d.setHours(0, 0, 0, 0)
    return d
  })
  
  // Search & Pagination State
  const [searchTerm, setSearchTerm] = useState('')
  const [selectedOpType, setSelectedOpType] = useState<string>('ALL')
  const [currentPage, setCurrentPage] = useState<number>(1)
  const [pageSize, setPageSize] = useState<number>(10)

  // Map of daily aggregate metrics { 'YYYY-MM-DD': { cost, input, output, count } }
  const dailyAggregates = useMemo(() => {
    const map: Record<string, { cost: number; input: number; output: number; count: number }> = {}
    logs.forEach(log => {
      const d = new Date(log.created_at)
      const key = toYMD(d)
      if (!map[key]) {
        map[key] = { cost: 0, input: 0, output: 0, count: 0 }
      }
      map[key].cost += Number(log.total_cost_usd || 0)
      map[key].input += log.input_tokens || 0
      map[key].output += log.output_tokens || 0
      map[key].count += 1
    })
    return map
  }, [logs])

  // Unique operation types for dropdown filter
  const uniqueOpTypes = useMemo(() => {
    const types = new Set<string>()
    logs.forEach(l => {
      if (l.operation_type) types.add(l.operation_type)
    })
    return Array.from(types).sort()
  }, [logs])

  // Calculate Overall Metrics (Today, This Week, This Month)
  const metrics = useMemo(() => {
    const now = new Date()
    const todayStr = toYMD(now)
    
    // Start of week (Sunday)
    const weekStart = new Date(now)
    weekStart.setDate(now.getDate() - now.getDay())
    weekStart.setHours(0, 0, 0, 0)

    // Start of month
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1)

    const res = {
      today: { cost: 0, input: 0, output: 0, count: 0 },
      week: { cost: 0, input: 0, output: 0, count: 0 },
      month: { cost: 0, input: 0, output: 0, count: 0 },
    }

    logs.forEach(log => {
      const cost = Number(log.total_cost_usd || 0)
      const logDate = new Date(log.created_at)
      const dateStr = toYMD(logDate)

      if (dateStr === todayStr) {
        res.today.cost += cost
        res.today.input += log.input_tokens || 0
        res.today.output += log.output_tokens || 0
        res.today.count += 1
      }
      if (logDate >= weekStart) {
        res.week.cost += cost
        res.week.input += log.input_tokens || 0
        res.week.output += log.output_tokens || 0
        res.week.count += 1
      }
      if (logDate >= monthStart) {
        res.month.cost += cost
        res.month.input += log.input_tokens || 0
        res.month.output += log.output_tokens || 0
        res.month.count += 1
      }
    })

    return res
  }, [logs])

  // Selected Date Metrics (if a fixed date is selected)
  const selectedDateMetrics = useMemo(() => {
    if (!selectedDate) return null
    return dailyAggregates[selectedDate] || { cost: 0, input: 0, output: 0, count: 0 }
  }, [selectedDate, dailyAggregates])

  // Filtered logs for the table
  const filteredLogs = useMemo(() => {
    return logs.filter(log => {
      // Date filter
      if (selectedDate) {
        const logDateStr = toYMD(new Date(log.created_at))
        if (logDateStr !== selectedDate) return false
      }

      // Operation type filter
      if (selectedOpType !== 'ALL' && log.operation_type !== selectedOpType) {
        return false
      }

      // Search term filter
      if (searchTerm.trim() !== '') {
        const term = searchTerm.toLowerCase()
        const matchOp = log.operation_type?.toLowerCase().includes(term)
        const matchModel = log.model_name?.toLowerCase().includes(term)
        const matchDoc = log.documents?.reference_number?.toLowerCase().includes(term)
        if (!matchOp && !matchModel && !matchDoc) return false
      }

      return true
    })
  }, [logs, selectedDate, selectedOpType, searchTerm])

  // Reset page number on filter change
  const handleFilterChange = (setter: () => void) => {
    setter()
    setCurrentPage(1)
  }

  // Pagination bounds
  const totalEntries = filteredLogs.length
  const totalPages = Math.max(1, Math.ceil(totalEntries / pageSize))
  const safeCurrentPage = Math.min(currentPage, totalPages)
  const startIndex = (safeCurrentPage - 1) * pageSize
  const endIndex = Math.min(startIndex + pageSize, totalEntries)
  const paginatedLogs = filteredLogs.slice(startIndex, endIndex)

  // Calendar Grid Generator
  const calendarDays = useMemo(() => {
    const year = calendarMonth.getFullYear()
    const month = calendarMonth.getMonth()

    const firstDayOfMonth = new Date(year, month, 1)
    const startingDayOfWeek = firstDayOfMonth.getDay() // 0 = Sun, 1 = Mon ...
    const daysInMonth = new Date(year, month + 1, 0).getDate()

    // 42 cells grid (6 weeks)
    const days = []
    const prevMonthDays = new Date(year, month, 0).getDate()

    // Previous month padding
    for (let i = startingDayOfWeek - 1; i >= 0; i--) {
      const dayNum = prevMonthDays - i
      const d = new Date(year, month - 1, dayNum)
      days.push({ date: d, isCurrentMonth: false, dateStr: toYMD(d) })
    }

    // Current month days
    for (let i = 1; i <= daysInMonth; i++) {
      const d = new Date(year, month, i)
      days.push({ date: d, isCurrentMonth: true, dateStr: toYMD(d) })
    }

    // Next month padding to fill 42 grid cells
    const remaining = 42 - days.length
    for (let i = 1; i <= remaining; i++) {
      const d = new Date(year, month + 1, i)
      days.push({ date: d, isCurrentMonth: false, dateStr: toYMD(d) })
    }

    return days
  }, [calendarMonth])

  const prevMonth = () => {
    setCalendarMonth(prev => new Date(prev.getFullYear(), prev.getMonth() - 1, 1))
  }

  const nextMonth = () => {
    setCalendarMonth(prev => new Date(prev.getFullYear(), prev.getMonth() + 1, 1))
  }

  const todayStr = toYMD(new Date())

  return (
    <div className="space-y-8">
      {/* Dynamic Header & Fixed Date Cost Explorer Banner */}
      <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-4">
        <div>
          <h1 className="text-[24px] font-[600] text-[var(--text-primary)] tracking-tight">Token Usage & Server Costs</h1>
          <p className="text-[14px] text-[var(--text-secondary)] mt-1">
            Track AI processing execution logs, inspect daily costs, and query operations by fixed dates.
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-3">
          {selectedDate && (
            <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-[var(--primary)]/10 border border-[var(--primary)]/30 text-[var(--primary)] text-xs font-semibold">
              <CalendarIcon size={14} />
              <span>Filtered Date: <strong>{selectedDate}</strong></span>
              <button 
                onClick={() => handleFilterChange(() => setSelectedDate(null))}
                className="hover:bg-[var(--primary)]/20 p-0.5 rounded transition-colors"
                title="Clear date filter"
              >
                <X size={14} />
              </button>
            </div>
          )}

          <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-[var(--radius-sm)] bg-[var(--warning-muted)] border border-[color-mix(in_srgb,var(--warning)_30%,transparent)] text-[var(--warning)] text-xs font-semibold shrink-0">
            <span className="h-2 w-2 rounded-full bg-[var(--warning)] animate-pulse" />
            [Dev Mode] System-Wide Operations
          </div>
        </div>
      </div>

      {/* Aggregate Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
        {/* Today Metrics */}
        <Card className="shadow-sm border-[var(--border)] bg-[var(--surface)] text-[var(--text-primary)]">
          <CardHeader className="pb-2 border-b border-[var(--border)] bg-[var(--bg)]/50">
            <CardTitle className="text-[13px] font-[600] text-[var(--text-primary)] uppercase tracking-wide flex items-center justify-between">
              <span>Today</span>
              <span className="text-[11px] font-normal text-[var(--text-muted)]">{metrics.today.count} ops</span>
            </CardTitle>
          </CardHeader>
          <CardContent className="pt-4 space-y-3">
            <div>
              <div className="text-[10px] font-[600] text-[var(--text-muted)] uppercase tracking-wider mb-1">Total Cost</div>
              <div className="text-[26px] font-[700] text-[var(--text-primary)]">${metrics.today.cost.toFixed(4)}</div>
            </div>
            <div className="grid grid-cols-2 gap-2 text-xs pt-2 border-t border-[var(--border)]">
              <div>
                <span className="text-[var(--text-muted)] block text-[10px] uppercase">Input</span>
                <span className="font-semibold text-[var(--text-secondary)]">{metrics.today.input.toLocaleString()}</span>
              </div>
              <div>
                <span className="text-[var(--text-muted)] block text-[10px] uppercase">Output</span>
                <span className="font-semibold text-[var(--text-secondary)]">{metrics.today.output.toLocaleString()}</span>
              </div>
            </div>
          </CardContent>
        </Card>
        
        {/* This Week Metrics */}
        <Card className="shadow-sm border-[var(--border)] bg-[var(--surface)] text-[var(--text-primary)]">
          <CardHeader className="pb-2 border-b border-[var(--border)] bg-[var(--bg)]/50">
            <CardTitle className="text-[13px] font-[600] text-[var(--text-primary)] uppercase tracking-wide flex items-center justify-between">
              <span>This Week</span>
              <span className="text-[11px] font-normal text-[var(--text-muted)]">{metrics.week.count} ops</span>
            </CardTitle>
          </CardHeader>
          <CardContent className="pt-4 space-y-3">
            <div>
              <div className="text-[10px] font-[600] text-[var(--text-muted)] uppercase tracking-wider mb-1">Total Cost</div>
              <div className="text-[26px] font-[700] text-[var(--text-primary)]">${metrics.week.cost.toFixed(4)}</div>
            </div>
            <div className="grid grid-cols-2 gap-2 text-xs pt-2 border-t border-[var(--border)]">
              <div>
                <span className="text-[var(--text-muted)] block text-[10px] uppercase">Input</span>
                <span className="font-semibold text-[var(--text-secondary)]">{metrics.week.input.toLocaleString()}</span>
              </div>
              <div>
                <span className="text-[var(--text-muted)] block text-[10px] uppercase">Output</span>
                <span className="font-semibold text-[var(--text-secondary)]">{metrics.week.output.toLocaleString()}</span>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* This Month Metrics */}
        <Card className="shadow-sm border-[var(--border)] bg-[var(--surface)] text-[var(--text-primary)]">
          <CardHeader className="pb-2 border-b border-[var(--border)] bg-[var(--bg)]/50">
            <CardTitle className="text-[13px] font-[600] text-[var(--text-primary)] uppercase tracking-wide flex items-center justify-between">
              <span>This Month</span>
              <span className="text-[11px] font-normal text-[var(--text-muted)]">{metrics.month.count} ops</span>
            </CardTitle>
          </CardHeader>
          <CardContent className="pt-4 space-y-3">
            <div>
              <div className="text-[10px] font-[600] text-[var(--text-muted)] uppercase tracking-wider mb-1">Total Cost</div>
              <div className="text-[26px] font-[700] text-[var(--text-primary)]">${metrics.month.cost.toFixed(4)}</div>
            </div>
            <div className="grid grid-cols-2 gap-2 text-xs pt-2 border-t border-[var(--border)]">
              <div>
                <span className="text-[var(--text-muted)] block text-[10px] uppercase">Input</span>
                <span className="font-semibold text-[var(--text-secondary)]">{metrics.month.input.toLocaleString()}</span>
              </div>
              <div>
                <span className="text-[var(--text-muted)] block text-[10px] uppercase">Output</span>
                <span className="font-semibold text-[var(--text-secondary)]">{metrics.month.output.toLocaleString()}</span>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Fixed Date Card */}
        <Card className={`shadow-sm border transition-all ${
          selectedDate 
            ? 'border-[var(--primary)] bg-[var(--surface)] ring-1 ring-[var(--primary)]/30' 
            : 'border-[var(--border)] bg-[var(--surface)]'
        }`}>
          <CardHeader className="pb-2 border-b border-[var(--border)] bg-[var(--bg)]/50 flex flex-row items-center justify-between">
            <CardTitle className="text-[13px] font-[600] text-[var(--text-primary)] uppercase tracking-wide flex items-center gap-1.5">
              <CalendarIcon size={14} className="text-[var(--primary)]" />
              <span>{selectedDate ? `Date: ${selectedDate}` : 'Fixed Date Cost'}</span>
            </CardTitle>
            {selectedDate && (
              <button 
                onClick={() => handleFilterChange(() => setSelectedDate(null))} 
                className="text-xs text-[var(--text-muted)] hover:text-[var(--text-primary)] transition-colors flex items-center gap-1"
              >
                <X size={12} /> Clear
              </button>
            )}
          </CardHeader>
          <CardContent className="pt-4 space-y-3">
            {selectedDateMetrics ? (
              <>
                <div>
                  <div className="text-[10px] font-[600] text-[var(--text-muted)] uppercase tracking-wider mb-1">Cost on {selectedDate}</div>
                  <div className="text-[26px] font-[700] text-[var(--primary)]">${selectedDateMetrics.cost.toFixed(4)}</div>
                </div>
                <div className="grid grid-cols-2 gap-2 text-xs pt-2 border-t border-[var(--border)]">
                  <div>
                    <span className="text-[var(--text-muted)] block text-[10px] uppercase">Operations</span>
                    <span className="font-semibold text-[var(--text-secondary)]">{selectedDateMetrics.count} ops</span>
                  </div>
                  <div>
                    <span className="text-[var(--text-muted)] block text-[10px] uppercase">Total Tokens</span>
                    <span className="font-semibold text-[var(--text-secondary)]">{(selectedDateMetrics.input + selectedDateMetrics.output).toLocaleString()}</span>
                  </div>
                </div>
              </>
            ) : (
              <div className="py-2 text-center text-[var(--text-muted)] space-y-2">
                <p className="text-xs">Select a date in the calendar below to view exact fixed date costs.</p>
                <input 
                  type="date" 
                  className="w-full text-xs px-2.5 py-1.5 rounded border border-[var(--border-strong)] bg-[var(--bg)] text-[var(--text-primary)] focus:outline-none focus:ring-1 focus:ring-[var(--primary)]"
                  onChange={(e) => {
                    if (e.target.value) {
                      handleFilterChange(() => setSelectedDate(e.target.value))
                    }
                  }}
                />
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Calendar View & Date Explorer Container */}
      <Card className="shadow-sm border-[var(--border)] bg-[var(--surface)] overflow-hidden">
        <CardHeader className="py-3 px-6 border-b border-[var(--border)] bg-[var(--bg)]/50 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-[var(--primary)]/10 text-[var(--primary)]">
              <CalendarIcon size={18} />
            </div>
            <div>
              <CardTitle className="text-[16px] font-[600] text-[var(--text-primary)]">
                Calendar View & Daily Cost Explorer
              </CardTitle>
              <p className="text-xs text-[var(--text-secondary)]">
                Click any day to view fixed date cost breakdown & filter operations log
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2 w-full sm:w-auto justify-between sm:justify-end">
            <div className="flex items-center gap-1 bg-[var(--bg)] border border-[var(--border)] rounded-md p-1">
              <button 
                onClick={prevMonth}
                className="p-1 rounded hover:bg-[var(--surface)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors"
                title="Previous Month"
              >
                <ChevronLeft size={16} />
              </button>
              <span className="text-xs font-semibold px-2 text-[var(--text-primary)] min-w-[110px] text-center">
                {calendarMonth.toLocaleString('en-US', { month: 'long', year: 'numeric' })}
              </span>
              <button 
                onClick={nextMonth}
                className="p-1 rounded hover:bg-[var(--surface)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors"
                title="Next Month"
              >
                <ChevronRight size={16} />
              </button>
            </div>

            <button 
              onClick={() => {
                const d = new Date()
                d.setDate(1)
                setCalendarMonth(d)
              }}
              className="text-xs px-2.5 py-1 rounded border border-[var(--border)] bg-[var(--bg)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors"
            >
              Today
            </button>
          </div>
        </CardHeader>

        <CardContent className="p-4 sm:p-6">
          {/* Days of Week Header */}
          <div className="grid grid-cols-7 gap-1 sm:gap-2 mb-2 text-center text-[11px] font-semibold uppercase tracking-wider text-[var(--text-muted)]">
            <div>Sun</div>
            <div>Mon</div>
            <div>Tue</div>
            <div>Wed</div>
            <div>Thu</div>
            <div>Fri</div>
            <div>Sat</div>
          </div>

          {/* 42-cell Grid */}
          <div className="grid grid-cols-7 gap-1 sm:gap-2">
            {calendarDays.map(({ date, isCurrentMonth, dateStr }) => {
              const dayAggregate = dailyAggregates[dateStr]
              const hasUsage = dayAggregate && dayAggregate.cost > 0
              const isSelected = selectedDate === dateStr
              const isToday = dateStr === todayStr

              return (
                <div
                  key={dateStr}
                  onClick={() => {
                    handleFilterChange(() => {
                      if (selectedDate === dateStr) {
                        setSelectedDate(null) // Toggle off if clicked twice
                      } else {
                        setSelectedDate(dateStr)
                      }
                    })
                  }}
                  className={`min-h-[64px] sm:min-h-[76px] p-1.5 sm:p-2 rounded-lg border text-left cursor-pointer transition-all flex flex-col justify-between ${
                    isSelected
                      ? 'border-[var(--primary)] bg-[var(--primary)]/10 ring-2 ring-[var(--primary)]/40 shadow-sm'
                      : isToday
                      ? 'border-[color-mix(in_srgb,var(--warning)_50%,transparent)] bg-[var(--warning-muted)]'
                      : isCurrentMonth
                      ? 'border-[var(--border)] bg-[var(--bg)] hover:bg-[var(--surface-hover)]'
                      : 'border-transparent bg-transparent opacity-40 hover:opacity-60'
                  }`}
                >
                  <div className="flex items-center justify-between">
                    <span className={`text-xs font-semibold ${
                      isToday 
                        ? 'text-[var(--warning)]'
                        : isCurrentMonth 
                        ? 'text-[var(--text-primary)]' 
                        : 'text-[var(--text-muted)]'
                    }`}>
                      {date.getDate()}
                    </span>
                    {isToday && (
                      <span className="text-[9px] px-1 py-0.2 rounded bg-[var(--warning-muted)] text-[var(--warning)] font-bold uppercase">
                        Today
                      </span>
                    )}
                  </div>

                  <div className="mt-1">
                    {hasUsage ? (
                      <div className="space-y-0.5">
                        <div className="text-[11px] sm:text-xs font-bold text-[var(--text-primary)] truncate">
                          ${dayAggregate.cost.toFixed(4)}
                        </div>
                        <div className="text-[9px] sm:text-[10px] text-[var(--text-secondary)] truncate">
                          {dayAggregate.count} op{dayAggregate.count > 1 ? 's' : ''} • {((dayAggregate.input + dayAggregate.output) / 1000).toFixed(1)}k tokens
                        </div>
                      </div>
                    ) : (
                      <span className="text-[10px] text-[var(--text-muted)] block pt-1">$0.00</span>
                    )}
                  </div>
                </div>
              )
            })}
          </div>
        </CardContent>
      </Card>

      {/* Operations Table with Pagination Controls */}
      <div className="bg-[var(--surface)] rounded-lg shadow-sm border border-[var(--border)] overflow-hidden">
        {/* Table Header Controls */}
        <div className="px-6 py-4 border-b border-[var(--border)] bg-[var(--bg)]/50 flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <h2 className="text-[16px] font-[600] text-[var(--text-primary)] flex items-center gap-2">
              <span>Recent Server Operations</span>
              <span className="text-xs font-normal px-2 py-0.5 rounded-full bg-[var(--bg)] border border-[var(--border)] text-[var(--text-secondary)]">
                {totalEntries} found
              </span>
            </h2>
            {selectedDate && (
              <p className="text-xs text-[var(--primary)] mt-0.5">
                Showing operations recorded on fixed date: <strong>{selectedDate}</strong>
              </p>
            )}
          </div>

          <div className="flex flex-wrap items-center gap-3">
            {/* Search Input */}
            <div className="relative">
              <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-[var(--text-muted)]" />
              <input
                type="text"
                placeholder="Search ops, model, doc..."
                value={searchTerm}
                onChange={(e) => handleFilterChange(() => setSearchTerm(e.target.value))}
                className="pl-8 pr-3 py-1.5 text-xs bg-[var(--bg)] text-[var(--text-primary)] border border-[var(--border-strong)] rounded-md focus:ring-2 focus:ring-[var(--primary)] outline-none w-48 sm:w-60"
              />
              {searchTerm && (
                <button 
                  onClick={() => handleFilterChange(() => setSearchTerm(''))}
                  className="absolute right-2 top-1/2 -translate-y-1/2 text-[var(--text-muted)] hover:text-[var(--text-primary)]"
                >
                  <X size={12} />
                </button>
              )}
            </div>

            {/* Operation Type Dropdown */}
            {uniqueOpTypes.length > 0 && (
              <div className="flex items-center gap-1.5">
                <Filter size={14} className="text-[var(--text-muted)]" />
                <select
                  value={selectedOpType}
                  onChange={(e) => handleFilterChange(() => setSelectedOpType(e.target.value))}
                  className="py-1.5 px-2.5 text-xs bg-[var(--bg)] text-[var(--text-primary)] border border-[var(--border-strong)] rounded-md focus:ring-2 focus:ring-[var(--primary)] outline-none"
                >
                  <option value="ALL">All Operations</option>
                  {uniqueOpTypes.map(op => (
                    <option key={op} value={op}>{op}</option>
                  ))}
                </select>
              </div>
            )}

            {/* Reset Filters */}
            {(selectedDate || searchTerm || selectedOpType !== 'ALL') && (
              <button
                onClick={() => handleFilterChange(() => {
                  setSelectedDate(null)
                  setSearchTerm('')
                  setSelectedOpType('ALL')
                })}
                className="text-xs px-2.5 py-1.5 rounded border border-[var(--border)] bg-[var(--bg)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors flex items-center gap-1"
                title="Reset all filters"
              >
                <RotateCcw size={12} /> Reset Filters
              </button>
            )}
          </div>
        </div>

        {/* Table Body */}
        <div className="overflow-x-auto">
          <table className="w-full text-left text-[14px]">
            <thead className="bg-[var(--bg)] text-[12px] uppercase text-[var(--text-muted)] font-[500] border-b border-[var(--border)]">
              <tr>
                <th className="px-6 py-3">Timestamp</th>
                <th className="px-6 py-3">Operation</th>
                <th className="px-6 py-3">Model</th>
                <th className="px-6 py-3">Tokens (In / Out)</th>
                <th className="px-6 py-3">Cost (USD)</th>
                <th className="px-6 py-3">Document Ref</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--border)]">
              {paginatedLogs.map((log) => (
                <tr key={log.id} className="hover:bg-[var(--surface-hover)] transition-colors">
                  <td className="px-6 py-4 whitespace-nowrap text-[var(--text-secondary)] text-xs">
                    {new Date(log.created_at).toLocaleString('en-US', { 
                      month: 'short', 
                      day: 'numeric', 
                      year: 'numeric', 
                      hour: '2-digit', 
                      minute: '2-digit',
                      second: '2-digit',
                      hour12: false 
                    })}
                  </td>
                  <td className="px-6 py-4">
                    <span className="inline-flex items-center px-2 py-1 rounded bg-[var(--bg)] border border-[var(--border)] text-[12px] font-medium text-[var(--text-primary)]">
                      {log.operation_type}
                    </span>
                  </td>
                  <td className="px-6 py-4 text-[var(--text-primary)] text-xs font-mono">
                    {log.model_name}
                  </td>
                  <td className="px-6 py-4 text-[var(--text-secondary)] text-xs">
                    {log.input_tokens?.toLocaleString()} / {log.output_tokens?.toLocaleString()}
                  </td>
                  <td className="px-6 py-4 text-[var(--text-primary)] font-semibold text-xs">
                    ${Number(log.total_cost_usd || 0).toFixed(6)}
                  </td>
                  <td className="px-6 py-4 text-[var(--text-secondary)] text-xs">
                    {(log as any).documents?.reference_number || 'N/A'}
                  </td>
                </tr>
              ))}
              {paginatedLogs.length === 0 && (
                <tr>
                  <td colSpan={6} className="px-6 py-12 text-center text-[var(--text-muted)] space-y-2">
                    <p className="text-sm font-medium">No operations found matching the current criteria.</p>
                    {(selectedDate || searchTerm || selectedOpType !== 'ALL') && (
                      <button
                        onClick={() => handleFilterChange(() => {
                          setSelectedDate(null)
                          setSearchTerm('')
                          setSelectedOpType('ALL')
                        })}
                        className="text-xs text-[var(--primary)] hover:underline"
                      >
                        Clear filters and view all logs
                      </button>
                    )}
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        {/* Pagination Toolbar */}
        <div className="px-6 py-3 border-t border-[var(--border)] bg-[var(--bg)]/50 flex flex-col sm:flex-row items-center justify-between gap-4 text-xs text-[var(--text-secondary)]">
          <div className="flex items-center gap-4">
            <span>
              Showing <strong className="text-[var(--text-primary)]">{totalEntries > 0 ? startIndex + 1 : 0}</strong> to <strong className="text-[var(--text-primary)]">{endIndex}</strong> of <strong className="text-[var(--text-primary)]">{totalEntries}</strong> entries
            </span>

            {/* Page Size Selector */}
            <div className="flex items-center gap-1.5">
              <span>Rows:</span>
              <select
                value={pageSize}
                onChange={(e) => {
                  setPageSize(Number(e.target.value))
                  setCurrentPage(1)
                }}
                className="py-1 px-2 text-xs bg-[var(--bg)] text-[var(--text-primary)] border border-[var(--border-strong)] rounded focus:ring-1 focus:ring-[var(--primary)] outline-none"
              >
                <option value={10}>10</option>
                <option value={25}>25</option>
                <option value={50}>50</option>
                <option value={100}>100</option>
              </select>
            </div>
          </div>

          {/* Navigation Controls */}
          <div className="flex items-center gap-1">
            <button
              onClick={() => setCurrentPage(1)}
              disabled={safeCurrentPage <= 1}
              className="px-2.5 py-1 rounded border border-[var(--border)] bg-[var(--surface)] text-[var(--text-primary)] hover:bg-[var(--surface-hover)] disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
            >
              First
            </button>
            <button
              onClick={() => setCurrentPage(prev => Math.max(1, prev - 1))}
              disabled={safeCurrentPage <= 1}
              className="px-2.5 py-1 rounded border border-[var(--border)] bg-[var(--surface)] text-[var(--text-primary)] hover:bg-[var(--surface-hover)] disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
            >
              Prev
            </button>

            <span className="px-3 py-1 font-semibold text-[var(--text-primary)]">
              Page {safeCurrentPage} of {totalPages}
            </span>

            <button
              onClick={() => setCurrentPage(prev => Math.min(totalPages, prev + 1))}
              disabled={safeCurrentPage >= totalPages}
              className="px-2.5 py-1 rounded border border-[var(--border)] bg-[var(--surface)] text-[var(--text-primary)] hover:bg-[var(--surface-hover)] disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
            >
              Next
            </button>
            <button
              onClick={() => setCurrentPage(totalPages)}
              disabled={safeCurrentPage >= totalPages}
              className="px-2.5 py-1 rounded border border-[var(--border)] bg-[var(--surface)] text-[var(--text-primary)] hover:bg-[var(--surface-hover)] disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
            >
              Last
            </button>
          </div>
        </div>
      </div>

      {/* Model Pricing Manager (ReadOnly as per user preference) */}
      <PricingManager initialPricing={initialPricing} readOnly={true} />
    </div>
  )
}
