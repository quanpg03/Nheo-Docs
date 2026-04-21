# 📄 AWS Infrastructure Standard — v1 (Historical Reference)

> **Estado:** Deprecado | Reemplazado por [v2-active.md](v2-active.md)
>
> Este archivo existe como referencia histórica. No aplicar a clientes nuevos.

---

## Stack v1

```
client-infra/
├── terraform/
│   └── main.tf         # EC2 t3.small, EBS gp2, puerto 22 abierto, sin IAM role
├── docker-compose.yml  # n8n + postgres + fastapi + nginx — sin log driver, sin health checks
├── python/
│   └── app/
│       └── core/
│           └── config.py  # Lee .env del disco
├── scripts/
│   └── backup.sh       # VACÍO — placeholder sin implementación
└── docs/
    └── runbook.md      # Genérico
```

---

## Componentes v1

**EC2 t3.small** — 2 vCPU burstable, 2 GB RAM. Sin swap. Créditos CPU se agotan bajo carga sostenida de n8n (caída a 20% de capacidad).

**EBS gp2 único** — Volumen raíz compartido entre SO, Docker, y datos de Postgres. Sin separación de IO.

**Docker Compose (4 servicios)** — n8n, postgres, fastapi, nginx. Sin log driver (logs locales). Sin health checks.

**Nginx + Certbot** — TLS manual. Auto-renew con historial de fallas silenciosas en algunas distros.

**Terraform básico** — Sin IAM role, sin Parameter Store, puerto 22 abierto.

**backup.sh vacío** — El archivo existe pero no ejecuta nada. Riesgo crítico: pérdida total de datos ante falla de disco.

**Sin observabilidad** — CloudWatch solo reporta CPU. Sin métricas de memoria, disco, swap. Sin alarmas.

---

## Limitaciones documentadas

| Limitación | Riesgo | Fix en v2 |
|---|---|---|
| t3.small créditos CPU se agotan | Servidor a 20% capacidad bajo carga | t4g.large performance sostenida |
| backup.sh vacío | Pérdida total de datos | pg_dump real a S3 + AWS Backup |
| Puerto 22 abierto | Superficie de ataque SSH | SSM Session Manager |
| .env con credenciales en disco | Exposición si se compromete la instancia | Parameter Store SecureString |
| Sin métricas de memoria/disco | OOM kills y disco lleno sin alerta | CloudWatch Agent |
| Logs Docker locales | Logs perdidos si muere el contenedor | awslogs driver |
| Sin alarmas | Incidentes detectados por el cliente | 5 alarmas CloudWatch |
| Sin Sentry | Stack traces no capturados | Sentry free tier |

---

## Workflow v1 (7 pasos)

1. Clonar template
2. Actualizar variables en main.tf
3. `terraform apply`
4. SSH a la instancia (puerto 22)
5. Copiar .env con credenciales
6. `docker compose up -d`
7. Verificar que los contenedores están corriendo
