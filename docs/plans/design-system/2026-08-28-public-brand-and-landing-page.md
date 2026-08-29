---
title: Public Brand and Landing Page
status: in-progress
created: 2026-08-28
updated: 2026-08-29
owners:
  - product
  - design
  - engineering
related:
  - ./2026-08-20-casechain-design-system-overhaul.md
---

# Public Brand and Landing Page

## Summary

Replace the existing public landing page with an image-led Civic Ink experience that introduces CaseChain through the story of a legal matter becoming clear. The public page uses the same visual contract as the product—deep-ink navigation, warm semantic surfaces, compact geometry, Geist typography, restrained hierarchy, and accessible interaction—while allowing artwork to carry more atmosphere than an operational workspace.

## Context and Goals

The current landing page is a dense collection of animated feature demonstrations and generic software language. It does not establish a memorable product point of view or create a clear transition into CaseChain's calm, evidence-led workspace.

The first implementation tranche covers the landing page. Authentication, invitation acceptance, and post-sign-up onboarding will adopt the same public brand layer in a subsequent tranche after the landing direction has been reviewed in the browser. Business logic, routes, authentication behavior, and data contracts are out of scope.

Success means the landing page feels premium and distinct, communicates the product without generic automation claims, performs well with image-heavy art direction, works from 320px through wide desktop viewports, and remains legible in light and dark appearances.

## Decisions

- Use a grounded, mature anime-inspired environmental illustration for the hero: a recognisable contemporary Indian GST-litigation office, realistic adult professionals, abundant case files, and bright natural daylight. Avoid character-driven anime tropes, childish exaggeration, stock-photo polish, and technology metaphors.
- Restrict the hero artwork and interface to Civic Ink's deep ink, warm paper, restrained blue-green, brass, and low-chroma neutral palette. Do not continue the earlier vermilion-thread motif in the hero.
- Let the hero artwork occupy the full initial viewport. Remove the separate top navigation bar and place brand identity, workspace creation, record exploration, and sign-in access inside the hero composition. Use a bordered Civic Ink surface at 70% opacity without backdrop blur so the office remains present behind the story.
- Treat Civic Ink as the complete public-page contract rather than a colour reference. Use product-scale controls, restrained display headings, compact section spacing, warm bordered surfaces, deep-ink explanatory panels, and contained compositions instead of glass, decorative brass, oversized typography, or campaign-style full-bleed sections.
- Use the central message “Follow the matter. Not the folders.” and describe CaseChain as a connected GST-litigation record rather than leading with artificial intelligence or abstract brand language.
- Structure the page as a continuous story: the limits of folders, a code-native comparison between disconnected files and a legible matter, visible chronology, a grounded product specimen, continuity of practice knowledge, human judgement, and a closing invitation. Prefer specific legal-operational explanation over shallow capability claims.
- Use generated artwork only for atmosphere and narrative. Essential content, product facts, and actions remain semantic HTML.
- Use `next/image` for responsive layout and optimization. Preload only the hero; eagerly discover the two lower story images without adding head preloads so responsive resizing and long-scroll previews remain reliable. Serve the matter-clarity artwork from a compact WebP master because the in-app browser blocks that asset's local optimization derivative.
- Keep motion limited to a brief initial copy reveal and restrained scroll-linked depth on artwork. Parallax is desktop-only, request-animation-frame throttled, capped at a small offset, and disabled on phones and whenever reduced motion is requested; UI surfaces and content never move with it.
- Preserve Civic Ink semantic tokens, compact radii, accessible focus, descriptive labels, and 44-pixel touch targets. A public page may use larger editorial typography while operational screens retain compact hierarchy.
- Treat the landing implementation as the source for the later authentication and invitation visual refresh; do not redesign those flows in this tranche.

## Implementation Plan

1. Generate and save coordinated public artwork, using the approved bright working-office hero direction and retaining supporting art only while it remains consistent with Civic Ink.
2. Replace the interactive feature-carousel landing page with a server-rendered editorial composition and semantic sections.
3. Add code-native disconnected-file, connected-matter, and illustrative chronology specimens that demonstrate the product without embedding essential text in imagery.
4. Update public metadata copy to match the new brand language.
5. Add a reduced-motion-safe initial reveal and restrained, artwork-only scroll depth without introducing layout shift or an additional scroll owner.
6. Verify image loading, responsive cropping, keyboard navigation, contrast, and scroll ownership in the in-app browser at phone and desktop sizes.
7. Use browser critique to revise composition and copy before carrying the visual direction into authentication and onboarding.

## Interfaces and Data Changes

None. The root route behavior remains unchanged: unauthenticated users see the landing page; authenticated users continue through the existing organisation and dashboard routing logic.

## Testing and Acceptance Criteria

- `npx tsc --noEmit`, scoped ESLint, `git diff --check`, and `npm run build` pass.
- The landing page has no page-level horizontal overflow at 320px, typical phone, tablet, desktop, and 200% zoom.
- Hero and section artwork retain useful crops across tested breakpoints and never contains essential text.
- Hero text meets WCAG 2.2 AA contrast against its Civic Ink paper field in light and dark appearances.
- Every link is keyboard reachable, visibly focused, descriptively labeled, and has an effective target of at least 44 by 44 pixels.
- Reduced-motion preference removes the initial reveal animation.
- Reduced-motion and phone presentations remove all scroll-linked artwork transforms.
- Only the hero image is preloaded; lower-page artwork uses responsive eager loading without head preloads.
- Light and dark appearances preserve readable semantic surfaces in the product specimen and closing sections.
- The page has one principal document scroller and no nested scrolling regions.

## Assumptions

- CaseChain initially serves Indian GST-litigation practices, and the imagery may carry an understated Indian architectural context without relying on legal clichés.
- The generated artwork is original project collateral and may be refined or replaced after visual critique.
- Signup remains the primary acquisition action and sign-in remains available inside the hero without requiring separate navigation chrome.

## Open Questions

None.
