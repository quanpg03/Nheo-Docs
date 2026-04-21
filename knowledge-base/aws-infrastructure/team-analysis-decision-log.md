# 🔍 Team Analysis & Decision Log

> **Autores:** Equipo Nheo (Juanes + equipo) | **Fecha:** Abril 2026

---

# Parte II — Propuestas del Equipo

## Propuesta 1 — Upgrade de compute

| Instancia | vCPU | RAM | USD/mes | Evaluación |
|---|---|---|---|---|
| t4g.large (ARM) | 2 | 8 GB | ~USD 49 | **ELEGIDA** — Graviton, performance sostenida |
| m6g.large (ARM) | 2 | 8 GB | ~USD 55 | Similar pero más caro |
| t3.medium (x86) | 2 | 4 GB | ~USD 33 | Solo 4 GB RAM |
| t3.large (x86) | 2 | 8 GB | ~USD 60 | Más caro que t4g sin ventaja |

También propuesto: Savings Plans 1 año (~30% ahorro) y 4 GB swap como red de seguridad gratuita.

## Propuesta 2 — Sacar PostgreSQL de la EC2

Opciones: Aurora Serverless v2 (~USD 45/mes idle), RDS Multi-AZ (~USD 30), RDS Single-AZ (~USD 18). Decisión: mantener en EC2 con volumen dedicado (ver Parte III).

## Propuesta 3 — Red y seguridad

- Cerrar puerto 22, usar SSM Session Manager
- ALB + ACM en lugar de Nginx+Certbot (~USD 18/mes)
- CloudFront + WAF (~USD 5/mes)
- Parameter Store SecureString para credenciales
- EBS gp3 en lugar de gp2
- VPC con subnet privada + NAT Gateway (~USD 33/mes)

## Propuesta 4 — Observabilidad

- CloudWatch Agent para mem/disk/swap/procesos
- Log driver awslogs en todos los servicios
- 5 alarmas mínimas
- Sentry free tier para errores FastAPI
- AWS X-Ray para tracing distribuido (opcional)

## Propuesta 5 — Backups reales

- AWS Backup para EBS, diario, retención 30 días
- pg_dump a S3 con lifecycle a Glacier Deep Archive tras 30 días
- Export diario de workflows n8n a JSON versionado
- Restore test bimestral documentado

## Propuesta 6 — n8n en modo queue

n8n standard ejecuta in-process: un workflow pesado bloquea todos los demás. Modo queue usa Redis + workers separados. Decisión: diferir.

## Propuesta 7 — Multi-tenant con ECS Fargate

EC2 por cliente a 20+ clientes es inmanejable. Fargate + Aurora schema-per-tenant ahorra 50-70%. Decisión: diferir con triggers corregidos.

---

# Parte III — Decisiones Finales

## Tabla consolidada

| # | Decisión | Estado |
|---|---|---|
| 14.1 | Upgrade a t4g.large (ARM Graviton) | ✅ ACEPTADO |
| 14.2 | Swap 4 GB en disco | ✅ ACEPTADO |
| 14.3 | Savings Plans 1 año | ⏳ DIFERIDO |
| 14.4-7 | Postgres en EC2 con volumen dedicado | ✅ ACEPTADO CON DESVIACIÓN |
| 14.8 | Cerrar SSH, usar SSM Session Manager | ✅ ACEPTADO |
| 14.9 | ALB + ACM en lugar de Nginx+Certbot | ⏳ DIFERIDO |
| 14.10 | CloudFront + WAF | ❌ RECHAZADO |
| 14.11 | Parameter Store SecureString | ✅ ACEPTADO CON MODIFICACIÓN |
| 14.12 | EBS gp3 en lugar de gp2 | ✅ ACEPTADO |
| 14.13 | VPC + NAT Gateway | ❌ RECHAZADO |
| 14.14 | CloudWatch Agent | ✅ ACEPTADO |
| 14.15 | awslogs driver en Docker Compose | ✅ ACEPTADO |
| 14.16 | 5 alarmas + alarma runner inactivo | ✅ ACEPTADO CON MODIFICACIÓN |
| 14.17 | Sentry free tier | ✅ ACEPTADO |
| 14.18 | AWS X-Ray | ❌ RECHAZADO |
| 14.19 | AWS Backup + pg_dump a S3 | ✅ ACEPTADO |
| 14.20 | Export diario workflows n8n | ✅ ACEPTADO |
| 14.21 | Restore test bimestral documentado | ✅ ACEPTADO CON MODIFICACIÓN |
| 14.22 | n8n modo queue (Redis + workers) | ⏳ DIFERIDO |
| 14.23 | ECS Fargate multi-tenant | ⏳ DIFERIDO |
| 14.24 | Aurora Serverless v2 schema-per-tenant | ⏳ DIFERIDO |

---

## Detalle por decisión

**14.1 — t4g.large [ACEPTADO]** — USD 34/mes de diferencia es trivial vs costo de un incidente. t3.small agota créditos CPU en minutos. t4g.large elimina ~80% del riesgo operativo.

**14.2 — Swap 4 GB [ACEPTADO]** — Gratis. Red de seguridad contra picos de memoria.

**14.3 — Savings Plans [DIFERIDO]** — Trigger: 3+ clientes con 6+ meses de historia estable.

**14.4-7 — Postgres en EC2 con volumen dedicado [ACEPTADO CON DESVIACIÓN]** — Ninguna opción gestionada justifica el costo para bases de 100 MB. Trigger RDS: >500 MB datos o requisito regulatorio.

**14.8 — SSM Session Manager [ACEPTADO]** — Puerto 22 es la superficie de ataque más común. SSM provee shell completo sin abrir puertos. Todo queda en CloudTrail.

**14.9 — ALB + ACM [DIFERIDO]** — USD 18/mes es 37% del costo base. Trigger: tráfico público real o arquitectura multi-tenant.

**14.10 — CloudFront + WAF [RECHAZADO]** — Sin assets estáticos que cachear. Tráfico es interno o autenticado. Se revisa junto con ALB.

**14.11 — Parameter Store SecureString [ACEPTADO CON MODIFICACIÓN]** — Secrets Manager cobra USD 0.40/secreto/mes sin valor adicional real. Parameter Store gratis para SecureString.

**14.12 — EBS gp3 [ACEPTADO]** — 20% más barato, 3000 IOPS base vs 100-150 IOPS de gp2 en volúmenes pequeños. Segundo volumen dedicado para Postgres.

**14.13 — VPC + NAT Gateway [RECHAZADO]** — NAT Gateway USD 33+/mes = 67% overhead sobre la EC2. SSM resuelve el acceso seguro.

**14.14 — CloudWatch Agent [ACEPTADO]** — Sin agente, servidor puede llegar al 95% RAM sin disparar alarma. Costo: ~USD 2/mes.

**14.15 — awslogs driver [ACEPTADO]** — Sin log driver los logs mueren con el contenedor. awslogs envía en tiempo real. Costo: ~USD 2/mes.

**14.16 — 5 alarmas + runner inactivo [ACEPTADO CON MODIFICACIÓN]** — Sin ALB, alarma de 5xx reemplazada por alarma de runner inactivo de n8n. Las 5: CPU >80%, mem >85%, disk >80%, CPU credits <20, runner inactivo.

**14.17 — Sentry free tier [ACEPTADO]** — CloudWatch no estructura errores. Sentry captura stack trace + contexto. 5,000 eventos/mes gratis. Dos líneas de integración.

**14.18 — AWS X-Ray [RECHAZADO]** — Flows actuales son simples. CloudWatch + Sentry suficientes para diagnosticar. X-Ray agrega complejidad sin valor proporcional.

**14.19 — AWS Backup + pg_dump [ACEPTADO]** — backup.sh vacío es el riesgo más grave del v1. EBS snapshot restaura rápido; pg_dump permite restaurar tabla específica.

**14.20 — Export workflows n8n [ACEPTADO]** — Workflows son el IP del servicio. Export a JSON permite versionar en git y restaurar en instancia nueva en minutos.

**14.21 — Restore test bimestral [ACEPTADO CON MODIFICACIÓN]** — Frecuencia cambiada de trimestral a bimestral. Un backup que nunca se ha restaurado es una promesa no verificada.

**14.22 — n8n modo queue [DIFERIDO]** — Trigger: workflow bloquea otros >2 min en producción, o SLA webhook <500ms.

**14.23 — ECS Fargate [DIFERIDO]** — Triggers (ambos): equipo dedica >4 hrs/mes en parcheo EC2 Y hay 3+ clientes con configuración idéntica.

**14.24 — Aurora Serverless v2 [DIFERIDO]** — Depende de 14.23. Trigger: Fargate activo Y 5+ clientes activos.

**Nota — Sesgo del documento original:** El análisis tiene sesgo hacia servicios gestionados de AWS. La bitácora aplica: la complejidad siempre tiene costo aunque no aparezca en la factura.

---

# Roadmap

## Fase 1 — Quick Win (esta semana)
- t4g.large ARM + AMI ARM64
- gp3 en todos los volúmenes + volumen EBS dedicado Postgres
- iam.tf con rol SSM + Parameter Store
- Puerto 22 cerrado
- 4 GB swap en user_data
- Credenciales a Parameter Store
- awslogs driver en todos los servicios
- Health checks en todos los contenedores

## Fase 2 — Production-Ready (semana 2, por cliente)
- CloudWatch Agent instalado
- 5 alarmas + SNS al equipo
- Sentry inicializado
- backup.tf + s3.tf aplicados
- backup.sh real probado
- export-workflows.sh como cron
- docs/decisions.md creado por cliente
- docs/restore-log.md creado

## Fase 3 — Scale Play (cliente 8+, trigger-gated)
- Savings Plans — trigger: 3+ clientes estables 6+ meses
- n8n modo queue — trigger: bloqueo observado en producción
- ALB + ACM — trigger: tráfico público real
- ECS Fargate — trigger: 4+ hrs/mes parcheo Y 3+ clientes idénticos
- Aurora Serverless v2 — trigger: Fargate activo Y 5+ clientes
- RDS Single-AZ — trigger: >500 MB datos o requisito regulatorio

## Lista NUNCA
- VPC + NAT Gateway como estándar (USD 33+/mes sin justificación)
- CloudFront + WAF como estándar (sin assets estáticos)
- AWS X-Ray (complejidad no justificada)
- RDS Multi-AZ como estándar (requisito de HA no existe)
- Secrets Manager como estándar (Parameter Store cubre el caso)
