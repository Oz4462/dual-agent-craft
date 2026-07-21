---
name: react-a11y
description: React work with accessibility as a gate, not an afterthought — semantic-first components, keyboard paths, WCAG 2.2 checks wired into review.
---
# React + A11y

## Build rules
- Semantic HTML first (`button`, `nav`, `label`); ARIA only where semantics can't reach. No `div onClick`.
- Every interactive element: keyboard path (Tab/Enter/Esc), visible focus state, accessible name.
- Forms: `label htmlFor`, error text linked via `aria-describedby`, never color-only signaling.
- Motion: respect `prefers-reduced-motion`; animate transform/opacity only.
- State: server state (query lib) ≠ client state ≠ URL state — don't duplicate; derive, don't store computed.
- Hooks: exhaustive deps honest (fix the cause, never silence the lint); stable callbacks for list children.

## Gate (before "done")
1. `eslint-plugin-jsx-a11y` clean (or documented exceptions).
2. Keyboard-only walkthrough of the changed flow.
3. Axe scan on the changed pages (jest-axe or browser ext) — 0 serious/critical.
4. Focus order + trap check on any modal/overlay touched.

## Review lens
Diff review asks: what breaks with screen reader, keyboard-only, 200% zoom, reduced motion? A component failing any of these is INCOMPLETE, not "works on my machine".
