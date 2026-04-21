# CLOSRADS

> Sincronización automática de regiones geográficas en Facebook Ads basada en demanda operativa.

**Estado:** En activación | **Owner:** Equipo Nheo

## Qué hace

CLOSRADS lee diariamente un archivo de demanda (`demand_response.json`) que mapea estados operativos a regiones de Facebook Ads. Cuando la demanda cambia, actualiza automáticamente el targeting geográfico de los ad sets activos, activando o desactivando regiones según corresponda.

## Documentación

- [GitHub Actions & CI/CD](github-actions.md)
- [Tests & Coverage](tests.md)
- [Activation Plan](activation-plan.md)
- [Design Decisions](design-decisions.md)
