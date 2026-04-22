# Nheo Automation Team — Docs

Central documentation repository for the Nheo Automation Team.
**This is the source of truth. Notion is no longer maintained.**

---

## Structure

```
Nheo-Docs/
├── knowledge-base/           # Technical standards and references
│   └── aws-infrastructure/   # AWS v2 template + decision log
├── projects/                 # Per-project documentation
│   ├── closrads/             # Facebook Ads Geo Sync
│   └── openclaw/             # ReadyMode Bot (Arpa Growth)
├── sops/                     # Standard Operating Procedures
└── research/                 # Pre-build research and investigations
```

---

## Quick Index

### Knowledge Base

| Document | Description |
|----------|-------------|
| [AWS Infrastructure v2](knowledge-base/aws-infrastructure/v2-active.md) | Active template — reference for new deployments |
| [AWS Infrastructure v1](knowledge-base/aws-infrastructure/v1-historical.md) | Original version — historical reference |
| [AWS Team Analysis & Decision Log](knowledge-base/aws-infrastructure/team-analysis-decision-log.md) | 7 proposals + 24-decision log |

### Projects — CLOSRADS

| Document | Description |
|----------|-------------|
| [Overview](projects/closrads/overview.md) | Project summary, background, status, dry-run results |
| [Architecture](projects/closrads/architecture.md) | Data flow, file structure, layer separation, execution sequence |
| [Module Reference](projects/closrads/module-reference.md) | Detailed docs for all 7 modules in `src/` |
| [GitHub Actions & CI/CD](projects/closrads/github-actions.md) | Workflow, secrets, IP whitelist problem, branch strategy |
| [Tests & Coverage](projects/closrads/tests.md) | 18 tests, offline strategy, fixtures, coverage gaps |
| [Activation Plan](projects/closrads/activation-plan.md) | 6 ordered steps to go live + blockers |
| [Design Decisions](projects/closrads/design-decisions.md) | D01–D10 with full reasoning |

### Projects — OpenClaw

| Document | Description |
|----------|-------------|
| [Overview](projects/openclaw/overview.md) | Project summary, requirements, support scenarios |
| [Operations](projects/openclaw/operations.md) | All 4 operations — status, selectors, blockers |
| [Architecture](projects/openclaw/architecture.md) | Execution flow, design decisions, server infra, 3-layer memory proposal |
| [Support Playbook](projects/openclaw/support-playbook.md) | 13 conversational support scenarios |
| [Incidents & Lessons Learned](projects/openclaw/incidents.md) | 10 Phase 1 incidents with root cause and fix |
| [Security Audit](projects/openclaw/security-audit.md) | 27 findings, 3-phase remediation plan |
| [Compliance Matrix](projects/openclaw/compliance-matrix.md) | R01–R33 (57% done, 30% TODO, 6% blocked) |
| [Gap Analysis & Roadmap](projects/openclaw/gap-analysis-roadmap.md) | G01–G13, prioritized roadmap, ~10–16 dev days |

### SOPs & Processes

| Document | Description |
|----------|-------------|
| [How We Work](sops/how-we-work.md) | Communication, task assignment, sprints, general rules |
| [Development Process](sops/development-process.md) | 6-step dev process + code standards |
| [Research Process](sops/research-process.md) | 5-step research process + page template |
| [Documentation Standards](sops/documentation-standards.md) | Rules + minimum requirements per project |

### Research

| Document | Description |
|----------|-------------|
| [Research Hub](research/README.md) | Index — one file per research topic |

---

## Repo Rules

- Everything in markdown (`.md`)
- One file per topic — do not mix projects
- Commit message format: `docs(project): description of change`
- Architecture decisions go in the relevant project file, not in PRs
- Never commit credentials or `.env` files
