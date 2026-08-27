---
title: Project Portal and GitHub Pages
status: in-progress
created: 2026-08-27
updated: 2026-08-27
owners:
  - product
  - engineering
related:
  - ../platform/2026-08-24-product-architecture-portfolio.md
---

# Project Portal and GitHub Pages

## Summary

Publish a lightweight, public, static Project Portal for friends and reviewers. It renders the repository's canonical plan archive and an explicit implementation snapshot without deploying or changing the CaseChain application on Vercel.

## Context and Goals

CaseChain currently has one `main` branch, which is connected to Vercel. Development will initially happen on a `dev` branch. Reviewers need a readable URL for plan status, full plan content, the current implementation report, and remaining work.

The portal must be fast, static, public only by deliberate choice, and independent of the Next.js runtime. It must not claim that an approved plan is implemented.

## Decisions

- A dependency-free Node.js build script reads `docs/plans/**/*.md` and `docs/project-portal-status.json`, then emits static HTML, CSS, and browser JavaScript into `project-portal/dist`.
- Existing plan frontmatter is the canonical source for plan title, status, and update date. The progress JSON is the explicit source for implementation claims and must be updated when delivery status changes.
- GitHub Actions deploys the static artifact to GitHub Pages after qualifying pushes to `dev`. It does not deploy the CaseChain application or modify Vercel.
- The Pages workflow has one active source branch at a time. When `dev` is merged and retired, change the workflow trigger to `main`; do not deploy both branches to the one Pages site concurrently.
- The public site offers a compact dashboard, status filtering, plan detail pages, a progress report, light/dark appearance, responsive layout, and source links.
- No credentials, user data, production secrets, or security-sensitive operational detail may be added to public portal content.

## Implementation Plan

1. Add the status snapshot, static build script, portal assets, and generated output ignore rule.
2. Build a responsive dashboard and plan reader directly from the archived Markdown files.
3. Add a GitHub Pages Actions workflow triggered by plan, portal, status, or workflow changes on `dev`.
4. Configure GitHub Pages to use GitHub Actions after the `dev` branch is pushed, then validate the deployed URL and small-screen presentation.
5. Update the status snapshot whenever a verifiable implementation milestone changes; retain links to canonical plans rather than copying their decisions into the portal.

## Interfaces and Data Changes

- `docs/project-portal-status.json`: public, manually maintained delivery snapshot with `updated`, `summary`, `implemented`, `active`, and `remaining` fields.
- `scripts/build-project-portal.mjs`: local/CI generator invoked with Node.js; it has no network, server, database, or application-runtime dependency.
- `.github/workflows/deploy-project-portal.yml`: GitHub Pages deployment workflow.

## Testing and Acceptance Criteria

- `node scripts/build-project-portal.mjs` succeeds from a clean checkout and creates an `index.html` plus one HTML page per archived plan.
- The dashboard counts plan statuses accurately, filter buttons work with keyboard and pointer input, and each plan has a readable detail page and source link.
- The page remains usable at 320px and wide desktop widths, supports visible focus, respects reduced motion, and exposes status as text as well as colour.
- A push to `dev` that changes portal inputs deploys only the Pages artifact; Vercel's `main` deployment configuration is unchanged.

## Assumptions

- The repository owner intentionally wants the selected portal content to be publicly shareable.
- GitHub Pages remains a single public project site for this repository.

## Open Questions

None.
