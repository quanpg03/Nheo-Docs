# Fleet Status

**Last updated:** 2026-08-06  
**Sources:** Informe_Tenants_Pendientes_2026-08-03, Informe_Operacion_Tickets_y_Credenciales_2026-08-05, Informe_Jornada_Asociacion_y_Colas_2026-08-06

---

## Summary

| Status | Count |
|---|---|
| Containers in operation | 15 |
| Messaging sessions active | 14 (Account O uses different codebase) |
| Ticket-channel access verified | 5 |
| Not yet mounted | 6 |
| Zero inventory (dialers not populated) | 2 (Hooper, Surf) |
| Total known accounts | 21 |

---

## Operating Accounts (15)

| Account | ReadyMode URL | Notes |
|---|---|---|
| jamesgaviria | jamesgaviria.readymode.com | Original fleet |
| zenithfinancial | zenithfinancial.readymode.com | Original fleet |
| factoredxprecision | factoredxprecision.readymode.com | Original fleet |
| factoredfinancial | factoredfinancial.readymode.com | Original fleet |
| precisioncapital | precisioncapital.readymode.com | Original fleet |
| thevine | thevine.readymode.com | Original fleet |
| jgfinancial | jgfinancial.readymode.com | Original fleet |
| enhancedialer | enhancedialer.readymode.com | Original fleet |
| theupperechelon | theupperechelon.readymode.com | Original fleet |
| ascenti | ascenti.readymode.com | Mounted 2026-08-03; 10,186 lists, 686 users, 36 campaigns |
| missedinbound | missedinbound.readymode.com | Mounted 2026-08-03; 3,498 lists, 97 agent-list associations |
| iul | iulnew.readymode.com | Mounted 2026-08-03; credential fixed 2026-08-05; 2,376 lists, 178 users, 16 campaigns |
| dominionco | dominionco.readymode.com | Discord auth was pending as of 2026-08-03; confirm current status |
| hooperdialer | hooperdialer.readymode.com | Added 2026-08-05; 0 lists (dialer not yet populated by client) |
| surferdialer | surferdialer.readymode.com | Added 2026-08-05; 0 lists (dialer not yet populated by client) |

---

## Not Yet Mounted (6)

Waiting on client action (credentials, Discord server invite, or dialer URL).

| Account |
|---|
| breaddialer |
| pioneerunited |
| ssps |
| astro |
| merchantfinancial |
| unityfinancial |

---

## Known Inventory Issues

| Account | Issue | Action required |
|---|---|---|
| hooperdialer | 0 lists — dialer not populated | Client must populate ReadyMode |
| surferdialer | 0 lists — dialer not populated | Client must populate ReadyMode |
| Account A (anonymous) | 1,328 users but only 115 lists (12.1% coverage). Was 284 lists in July — lists were deleted or moved by the client, not a bot bug | Conversation with client needed |
| 4 accounts (names TBD) | No queue links discovered during 2026-08-06 sweep | Panel inspection required per account |
| 3 accounts (names TBD) | Do not accept the unified service account credentials | Per-account credentials required from client |

---

## Messaging Account Association (2026-08-06)

The messaging system maps Discord usernames to ReadyMode agent names. Correspondences are seeded manually and discovered automatically at 4 confidence levels.

| Metric | Value |
|---|---|
| Total messaging identities active (last 30 days) | 428 |
| Rows resolving to a real agent | 257 / 260 |
| Association rate | 60.0% (up from 24.3% before 2026-08-06 session) |
| New correspondences seeded | 175 |
| Current failure rate | 2.5% (down from 10.1% before name-correction deploy) |

Correspondence confidence breakdown: exact match (127), unique first name (68), abbreviated surname (20), exact surname (10), discarded (29).

The ceiling at ~60% is expected until "ask when unknown" behavior is implemented. See [`gap-analysis-roadmap.md`](./gap-analysis-roadmap.md) gap G-NEW-03.

---

## Test Coverage History

| Date | Event | Test cases |
|---|---|---|
| 2026-08-03 (before) | Baseline | 255 |
| 2026-08-03 (after) | Added ALLOWED_CHANNEL_REGEX + 3 new accounts | 271 |
| 2026-08-05 | Ticket access + iul fix + Hooper + Surf | — |
| 2026-08-06 | Queue discovery fixes (3 bugs) | 382 |
