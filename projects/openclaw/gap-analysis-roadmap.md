# Gap Analysis & Roadmap

This document covers every piece of missing functionality as of 2026-04-16, the blocker or reason it isn't done, the estimated effort, and the prioritized plan to close each gap.

---

## Gap Inventory (G01–G13)

| ID | Gap | Type | Blocker | Est. effort |
|----|-----|------|---------|-------------|
| G01 | Create User: create playlist with agent name | Feature | Charlie must send screenshots of playlist UI | 1–2 days |
| G02 | Create User: drag-and-drop campaigns to playlist | Feature | Unknown DOM selectors + CDP drag complexity | 2–3 days |
| G03 | Create User: drag-and-drop states to playlist | Feature | Same blocker as G02 | Included in G02 |
| G04 | Create User: assign user to playlist + verify "1 member" | Feature | Depends on G01–G03 | 0.5 days |
| G05 | Reset Leads: map Office Map selectors + implement | Feature | Charlie must assign agents to Office Map | 1–2 days |
| G06 | Upload Leads: handle non-standard CSV headers | Feature | Need sample CSV with custom headers from Charlie | 1 day |
| G07 | Upload Leads: create new campaign | Feature | No external blocker | 0.5–1 day |
| G08 | Upload Leads: merge duplicates | Feature | No external blocker | 0.5 days |
| G09 | Upload Leads: accept duplicates | Feature | No external blocker | 0.5 days |
| G10 | Upload Leads: search lead + move to campaign | Feature | Need to map search and move UI | 1–2 days |
| G11 | Call results: automate type A/B/normal assignment | Ambiguous | Confirm with client if automation is required or KB is sufficient | 1–2 days |
| G12 | Create dedicated bot account in ReadyMode | Infra | Coordination with Charlie | 0.5 days |
| G13 | Create User: additional fields (AMD, Dialing Rate) | Feature | Client has not confirmed spec | 1–2 days |

**Total estimated effort (once unblocked):** ~10–15 development days

---

## Priority 1 — Unblock (Requires Client Action)

These cannot be started without input from Charlie. Escalate immediately.

| # | Action | Owner | Urgency | Gaps unblocked |
|---|--------|-------|---------|----------------|
| 1 | Request playlist UI screenshots from Charlie (where "Add a Playlist" appears, where campaigns/states are dragged, where user is assigned) | Team → Charlie | 🔴 URGENT | G01, G02, G03, G04 |
| 2 | Request Charlie to assign agents to Office Map in ReadyMode | Team → Charlie | 🟠 HIGH | G05 |
| 3 | Request sample CSV with non-standard headers from Charlie | Team → Charlie | 🟡 MEDIUM | G06 |
| 4 | Confirm with client: should call results assignment be automated in UI or is KB-only sufficient? | Team → Client | ⚪ LOW | G11 |

---

## Priority 2 — Implement Now (No External Blocker)

These can be worked on immediately, in parallel with waiting for client responses.

| # | Task | Gaps covered | Est. effort |
|---|------|-------------|-------------|
| 5 | Upload Leads: create new campaign | G07 | 0.5–1 day |
| 6 | Upload Leads: merge + accept duplicates | G08, G09 | 1 day |
| 7 | Upload Leads: search + move leads | G10 | 1–2 days |
| 8 | Create dedicated bot account in ReadyMode | G12 | 0.5 days |

**Total for Priority 2:** ~3–4.5 days

---

## Priority 3 — Implement Post-Unblock (Depends on Client)

These require the client actions from Priority 1 to be completed first.

| # | Task | Gaps covered | Est. effort |
|---|------|-------------|-------------|
| 9 | Create User v3: playlist creation + drag-and-drop + user assignment | G01, G02, G03, G04 | 3–5 days |
| 10 | Reset Leads: map selectors + full implementation | G05 | 1–2 days |
| 11 | Upload Leads: non-standard header mapping modal | G06 | 1 day |
| 12 | Create User: additional fields (AMD, Dialing Rate) — only if spec confirmed | G13 | 1–2 days |
| 13 | Call results: automated UI assignment — only if client confirms required | G11 | 1–2 days |

**Total for Priority 3 (post-unblock):** ~7–12 days

---

## Effort Summary

| Priority | Description | Est. effort |
|----------|-------------|-------------|
| P1 | Client actions required (team to request) | 0 dev days (waiting) |
| P2 | Independent — can start now | 3–4.5 days |
| P3 | Dependent on client unblocking P1 | 7–12 days |
| **Total** | **Full gap closure** | **~10–16 days** |

> **Critical path:** G01–G04 (Create User playlist) is the highest-value work and the most blocked. Without Charlie's screenshots, this cannot move. The team should treat the screenshot request as the most urgent communication to the client right now.
