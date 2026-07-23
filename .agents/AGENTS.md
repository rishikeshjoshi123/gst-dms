# UI / UX Guidelines & Design Direction

Always use this UI pattern as the application development proceeds further.

## 1. Desktop Application Layout (MS Excel / Figma Desktop Feel)
- **Viewport Container**: Solid `h-screen w-full overflow-hidden` container. The outer window MUST NOT scroll or shake when browsing or interacting.
- **Fixed Toolbars & Action Bars**: Page title headers, navigation sidebars, action toolbars, and table headers stay **hard-fixed (`shrink-0 z-10`)**.
- **Inner Panel Scrolling**: Internal content areas scroll independently using subtle custom scrollbars (`scrollbar-none` or `custom-scrollbar`), maintaining zero layout shift.

## 2. Color System & Dark Mode
The app supports seamless Light and Dark mode themes:

### Light Mode Tokens:
- **Background**: `#FAFAF9` (warm white)
- **Surface (cards)**: `#FFFFFF` with shadow: `0 2px 8px rgba(0,0,0,0.06)`
- **Border**: `#E5E2DC` (warm gray)
- **Border-strong**: `#C9C5BE` (inputs at rest)
- **Sidebar bg**: `#1C1917` (warm stone-900)
- **Primary action**: `#1D4ED8` (deep blue) or gradient `linear-gradient(135deg, #1D4ED8 0%, #3B82F6 100%)`
- **Text primary**: `#1C1917`
- **Text secondary**: `#78716C`
- **Text muted**: `#A8A29E`

### Dark Mode Tokens (`.dark`):
- **Background**: `#0B0F17` (obsidian midnight)
- **Surface (cards)**: `#161E2E` / `#1E293B` with ambient glow shadow
- **Border**: `#1F293D` / `#334155`
- **Border-strong**: `#475569`
- **Sidebar bg**: `#0F172A`
- **Primary action**: `#3B82F6` or gradient `linear-gradient(135deg, #2563EB 0%, #4F46E5 100%)`
- **Text primary**: `#F8FAFC`
- **Text secondary**: `#94A3B8`
- **Text muted**: `#64748B`

## 3. Vibrant Gradients, Ambient Shadows & Processing Animations
- **Animated Gradient Borders**: For active processing/pipeline operations (e.g. document analysis, queue processing), wrap containers in multi-color animated gradient borders (`.animated-gradient-border`).
- **Ambient Gradient Shadows**: Key stat cards and primary action cards feature subtle colored ambient shadows (`shadow-[0_8px_30px_rgba(59,130,246,0.15)]` or `dark:shadow-[0_8px_30px_rgba(59,130,246,0.25)]`).
- **Litigation Graph Aesthetics**: Node borders use subtle gradient accents; graph connector lines use animated flowing SVG gradients (`stroke: url(#edge-gradient)`).

## 4. Toast Notifications
- Styled Sonner toasts with custom left-accent borders, dark mode compatibility, and smooth slide-in animations.

## 5. Sidebar & Topbar
- **Sidebar**: Fixed navigation with active amber accent border (`2px #F97316`).
- **Topbar**: Fixed `48px` header with breadcrumbs, org switcher, and one-click Theme Toggle (Light / Dark mode).
