# UI / UX Guidelines & Design Direction

Always use this UI pattern as the application development proceeds further.

## 1. Color Tokens
Commit to these exact tokens. Do not default to dark mode (light mode only for main UI, dark mode only for sidebar). Do not use glassmorphism.
- **Background**: `#FAFAF9` (warm white)
- **Surface (cards)**: `#FFFFFF` with shadow: `0 1px 3px rgba(0,0,0,0.08)`
- **Border**: `#E5E2DC` (warm gray)
- **Border-strong**: `#C9C5BE` (for inputs at rest)
- **Sidebar bg**: `#1C1917` (warm near-black, like stone-900)
- **Sidebar text**: `#E7E5E4`
- **Sidebar active**: `#292524` with left border `2px #F97316` (amber accent)
- **Primary action**: `#1D4ED8` (deep blue — authoritative)
- **Primary hover**: `#1E40AF`
- **Danger**: `#DC2626`
- **Text primary**: `#1C1917`
- **Text secondary**: `#78716C`
- **Text muted**: `#A8A29E`

## 2. Typography
Three sizes, three weights, nothing else:
- **Page title**: `24px / 600`
- **Section heading**: `16px / 600`
- **Body**: `14px / 400`
- **Caption/label**: `12px / 500` (uppercase for labels, normal case for descriptions)

## 3. Sidebar & Topbar
- **Sidebar**: The single source of navigation authority. Has the org name and switcher at the top, navigation in the middle, and user info at the bottom.
  - *Rest*: text only, no background
  - *Hover*: very subtle background `#292524`
  - *Active*: `#292524` background + `2px` left amber border + text in white
- **Topbar**: Stripped down to a 48px bar that only shows the current page breadcrumb on the left and the user avatar on the right — no logo, no org name.

## 4. Modals and Forms
One consistent component:
- White background, `rounded-lg`, `shadow-xl` (not a flat box)
- Title `18px/600`, subtitle `14px/400` in muted color
- **Inputs**: white background, 1px solid `#C9C5BE` border at rest, 2px solid `#1D4ED8` ring on focus, 4px border radius
- **Required fields**: a small red asterisk, not just "required" text
- **Action buttons** right-aligned: secondary (outlined) on left, primary (filled blue) on right

## 5. Cards
Two types, used consistently:
- **Stat card (dashboard metrics)**: white, subtle shadow, large number in `32px/700`, label in `12px/500` muted uppercase, a directional arrow icon top-right that links to the relevant page. Cards representing action items get a thin amber left border.
- **List card (clients, matters, documents)**: white, 1px warm gray border, 12px padding, hover state adds a faint shadow and shifts the chevron right by 2px. Show secondary information (matter count, open matters count, last document date).
