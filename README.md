# Nheo Automation Team — Knowledge Base

> Documentación central del equipo de automatización de Nheo.

## Estructura

```
Nheo/
├── knowledge-base/          # Estándares, templates y referencias técnicas
│   └── aws-infrastructure/  # Template AWS v2 + historial de decisiones
├── projects/                # Documentación por proyecto
│   ├── closrads/
│   └── openclaw/
└── research-hub/            # Investigaciones pre-build
```

## Índice rápido

| Documento | Descripción |
|---|---|
| [AWS Infrastructure v2](knowledge-base/aws-infrastructure/v2-active.md) | Template activo — referencia para nuevos clientes |
| [AWS Infrastructure v1](knowledge-base/aws-infrastructure/v1-historical.md) | Versión original — referencia histórica |
| [AWS Team Analysis & Decisions](knowledge-base/aws-infrastructure/team-analysis-decision-log.md) | Propuestas del equipo + bitácora de 24 decisiones |
| [CLOSRADS](projects/closrads/overview.md) | Sincronización automática de regiones Facebook Ads |
| [OpenClaw](projects/openclaw/overview.md) | Agent gateway multi-canal |

## Reglas del repo

- Todo en markdown (`.md`)
- Un archivo por tema — no mezclar proyectos
- Commit message: `docs(proyecto): descripción del cambio`
- Las decisiones de arquitectura van en el archivo correspondiente, no en PRs
