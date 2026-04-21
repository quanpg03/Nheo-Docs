# ☁️ AWS Infrastructure Standard — v2 (Active)

> **Estado:** Activo | **Versión:** 2.0 | **Última actualización:** Abril 2026
>
> Este es el template que se aplica a cada cliente nuevo. La v1 está en [v1-historical.md](v1-historical.md).

---

## Stack v2 — Resumen ejecutivo

| Componente | v1 | v2 | Razón |
|---|---|---|---|
| EC2 | t3.small (x86) | t4g.large (ARM Graviton) | Performance sostenida, 8 GB RAM |
| Storage | gp2 único | gp3 raíz + gp3 dedicado Postgres | 20% más barato, IOPS separados |
| Acceso | SSH puerto 22 | SSM Session Manager | Sin superficie de ataque |
| Credenciales | .env en disco | Parameter Store SecureString | Sin credenciales en texto plano |
| Logs | Docker local | awslogs → CloudWatch | Centralizado, buscable, con retención |
| Métricas | CPU solamente | CPU + mem + disk + swap | Visibilidad real |
| Alertas | Ninguna | 5 alarmas CloudWatch + SNS | Detección proactiva |
| Errores app | Ninguno | Sentry free tier | Stack traces con contexto |
| Backups | backup.sh vacío | AWS Backup + pg_dump a S3 | Backup real y verificable |
| Workflows n8n | Sin export | export-workflows.sh diario | IP del cliente versionado |
| Restore test | Nunca | Bimestral documentado | Backup verificado |
| IAM | Sin rol | Rol SSM + Parameter Store + S3 + CW | Acceso seguro sin credenciales estáticas |

---

## Estructura de archivos

```
client-infra/
├── terraform/
│   ├── main.tf              # EC2 t4g.large, EBS gp3, security group sin puerto 22
│   ├── iam.tf               # Rol IAM: SSM + Parameter Store + S3 + CloudWatch
│   ├── parameter_store.tf   # SecureStrings por cliente
│   ├── backup.tf            # AWS Backup diario, retención 30 días
│   ├── s3.tf                # Bucket backups + lifecycle Glacier 30 días
│   └── cloudwatch.tf        # 5 alarmas + log groups + SNS
├── docker-compose.yml       # n8n + postgres + fastapi + nginx — awslogs + health checks
├── python/
│   └── app/
│       ├── core/
│       │   ├── config.py    # Lee credenciales de Parameter Store en boot
│       │   └── logging.py   # logging estructurado + Sentry SDK
│       └── ...
├── scripts/
│   ├── backup.sh            # pg_dump → gzip → S3
│   ├── export-workflows.sh  # n8n CLI → JSON → S3
│   └── restore-test.sh      # S3 → Postgres temporal → verificar row counts
└── docs/
    ├── decisions.md         # ADR del cliente
    ├── restore-log.md       # Log de restore tests bimestrales
    └── runbook.md           # Procedimientos operativos
```

---

## Cambios por archivo (v1 → v2)

### terraform/main.tf
- `instance_type`: `t3.small` → `t4g.large`
- `ami`: AMI x86 → AMI ARM64 Amazon Linux 2023
- `volume_type`: `gp2` → `gp3`
- Nuevo: `aws_ebs_volume` dedicado para Postgres (gp3, 20 GB)
- Nuevo: `aws_volume_attachment` monta volumen en `/dev/xvdb`
- Nuevo: `iam_instance_profile` con rol SSM + Parameter Store
- Security group: eliminar regla ingress port 22

### terraform/iam.tf (NUEVO)
- `aws_iam_role` con trust policy para EC2
- Permisos: `ssm:*`, `ssm:GetParameter`, `s3:PutObject/GetObject`, `cloudwatch:PutMetricData`
- `aws_iam_instance_profile` asociado a la EC2

### terraform/parameter_store.tf (NUEVO)
- Un `aws_ssm_parameter` por secreto: DB password, API keys, Slack webhook
- Todos `type = "SecureString"` con KMS key por defecto
- Naming: `/{client}/{env}/{service}/{key}`

### terraform/backup.tf (NUEVO)
- `aws_backup_vault` + `aws_backup_plan` diario 2 AM UTC, retención 30 días
- `aws_backup_selection`: volumen raíz + volumen Postgres

### terraform/s3.tf (NUEVO)
- `aws_s3_bucket` para backups: `{client}-backups-{account_id}`
- Lifecycle: `pg_dump/` → Glacier Deep Archive tras 30 días
- Bloqueo acceso público + versioning habilitado

### terraform/cloudwatch.tf (NUEVO)
- 5 alarmas: CPU >80%, mem >85%, disk >80%, CPU credits <20, runner inactivo
- `aws_cloudwatch_log_group` por servicio Docker, retención 30 días
- SNS topic → correo del equipo

### docker-compose.yml
- Todos los servicios: bloque `logging` con driver `awslogs`
- Postgres: bind mount → `/mnt/postgres-data` (volumen EBS dedicado)
- Credenciales: inyectadas en boot via `core/config.py`
- Health checks en todos los servicios

### python/app/core/config.py
- v1: lee `.env` del disco
- v2: llama `boto3.client('ssm').get_parameters_by_path()` en boot. Fallback a env vars para desarrollo local.

### python/app/core/logging.py (NUEVO)
- `logging.basicConfig` estructurado
- Sentry SDK inicializado con DSN desde Parameter Store

### scripts/backup.sh (REESCRITO)
- `pg_dump` → gzip → `aws s3 cp` a `pg_dump/{date}/{client}.sql.gz`
- Reporta éxito/falla a CloudWatch Metrics custom
- Cron diario 3 AM

### scripts/export-workflows.sh (NUEVO)
- n8n CLI exporta workflows a JSON → S3 `n8n-workflows/{date}/`
- Cron diario 3:30 AM

### scripts/restore-test.sh (NUEVO)
- Baja dump de S3 → restaura en Postgres temporal → verifica row counts
- Diseñado para ejecución manual bimestral

### docs/decisions.md (NUEVO)
ADR por cliente. Formato: fecha, decisión, alternativas, razón.

### docs/restore-log.md (NUEVO)
Log de restore tests. Columnas: fecha, ejecutado por, desde backup del, tiempo, tablas verificadas, resultado.

### docs/runbook.md (ACTUALIZADO)
Incluye: acceso via SSM, rotación de credenciales en Parameter Store, escalar EBS, habilitar n8n queue mode, checks post-deploy.

---

## Workflow de onboarding (10 pasos)

1. Clonar template base
2. Renombrar variables `client_name` y `env` en Terraform
3. Crear parámetros en Parameter Store con credenciales del cliente
4. `terraform init && terraform apply`
5. Verificar IAM role asociado a la EC2
6. Acceso via SSM para montar volumen Postgres en `/mnt/postgres-data`
7. `docker compose up -d`
8. Verificar health checks de todos los servicios
9. Probar backup manual: `./scripts/backup.sh` → verificar dump en S3
10. Crear `docs/decisions.md` con decisiones específicas del cliente

---

## Regla de oro

> Nunca hay credenciales en el repositorio ni en variables de entorno en texto plano. Todo pasa por Parameter Store. El acceso a la instancia es siempre via SSM — nunca SSH directo.
