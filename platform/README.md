# GYMPT Platform Infrastructure

This directory contains the platform-level infrastructure for the GYMPT application, including monitoring, logging, and auto-remediation systems.

## Directory Structure

```
platform/
├── monitoring/          # Prometheus, Grafana, Alertmanager
├── logging/            # CloudWatch Logs, Athena, Fluent Bit
├── remediation/        # Auto-remediation worker configuration
└── README.md          # This file
```

## Overview

### Monitoring (`monitoring/`)

Complete observability stack using kube-prometheus-stack:

- **Prometheus**: Metrics collection, storage, and querying
- **Grafana**: Visualization dashboards
- **Alertmanager**: Alert routing and notification
- **ServiceMonitors**: Service discovery for metrics scraping
- **PrometheusRules**: Alerting rules

**Key Files:**
- `values-dev.yaml`: Helm values for kube-prometheus-stack
- `servicemonitor-*.yaml`: Service discovery configs (backend-api, agent-service, posture-analysis, workers)
- `prometheusrule-*.yaml`: Alert definitions (backend, infrastructure)
- `dashboard-*.json`: Grafana dashboards (EKS, API latency, JVM, GPU, Redis, SQS)

**Deploy:**
```bash
cd monitoring

# Install kube-prometheus-stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f values-dev.yaml

# Apply ServiceMonitors and PrometheusRules
kubectl apply -f servicemonitor-backend-api.yaml
kubectl apply -f servicemonitor-agent-service.yaml
kubectl apply -f servicemonitor-posture-analysis.yaml
kubectl apply -f servicemonitor-workers.yaml
kubectl apply -f prometheusrule-backend.yaml
kubectl apply -f prometheusrule-infrastructure.yaml
```

**Access Grafana:**
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Default credentials:
# Username: admin
# Password: prom-operator
```

---

### Logging (`logging/`)

Multi-tier logging architecture with CloudWatch Logs, S3 export, and Athena querying:

- **Fluent Bit**: Container log collection (DaemonSet)
- **CloudWatch Logs**: Real-time log storage and search
- **S3**: Long-term log archival
- **Athena**: SQL queries over historical logs
- **Glue**: Automated schema discovery

**Key Files:**
- `README.md`: Complete logging documentation with example queries
- `fluent-bit-values.yaml`: Optional enhanced Fluent Bit configuration

**Log Groups:**
- `/aws/eks/gympt-dev-eks/backend-api`
- `/aws/eks/gympt-dev-eks/agent-service`
- `/aws/eks/gympt-dev-eks/posture-analysis`
- `/aws/eks/gympt-dev-eks/report-service`
- `/aws/eks/gympt-dev-eks/workers`

**View Logs:**
```bash
# Real-time tail
aws logs tail /aws/eks/gympt-dev-eks/backend-api --follow

# CloudWatch Insights query
# (use AWS Console or CLI)
```

**Query Historical Logs (Athena):**
```sql
SELECT timestamp, level, message
FROM backend_api
WHERE level = 'ERROR'
  AND timestamp >= NOW() - INTERVAL '24' HOUR
ORDER BY timestamp DESC
LIMIT 100;
```

**Query Security Logs in Grafana:**

Grafana provisions the `Athena` datasource with the `grafana-athena-datasource` plugin. It uses AWS SDK default auth through the Grafana service account IRSA role and queries `gympt_prod_catalog` through `gympt-prod-workgroup`.

Use partition predicates for WAF and Inspector panels to keep Athena scan cost bounded:

```sql
SELECT
  from_unixtime(timestamp / 1000) AS time,
  action,
  httprequest.clientip AS client_ip,
  httprequest.uri AS uri
FROM waf_alb_logs
WHERE year='2026'
  AND month='06'
  AND day='08'
  AND hour='00'
LIMIT 100;
```

---

### Remediation (`remediation/`)

Automated remediation system that responds to Prometheus alerts:

- **Remediation Worker**: Python FastAPI service
- **Alert Rules**: Alert-to-action mappings
- **Runbooks**: Operational procedures

**Key Files:**
- `values-dev.yaml`: Helm values for remediation-worker
- `alert-rules.yaml`: Alert-to-action mapping configuration
- `runbooks.md`: Detailed operational runbooks for each alert

**Supported Actions:**
1. `restart_deployment`: Rolling restart
2. `scale_deployment`: Scale up/down
3. `rollback_argocd`: Rollback via Argo CD
4. `notify_only`: Slack notification
5. `patch_deployment`: Apply JSON patch

**Deploy:**
```bash
cd remediation

# Create secrets
kubectl create secret generic remediation-secrets \
  -n workers \
  --from-literal=slack-webhook-url=$SLACK_WEBHOOK_URL \
  --from-literal=argocd-auth-token=$ARGOCD_TOKEN

# Deploy (using Helm chart in gympt-charts repo)
helm install remediation-worker gympt/remediation-worker \
  -n workers --create-namespace \
  -f values-dev.yaml

# Apply alert rules ConfigMap
kubectl create configmap alert-rules \
  -n workers \
  --from-file=alert-rules.yaml

# Restart to load new rules
kubectl rollout restart deployment/remediation-worker -n workers
```

**Test:**
```bash
# Port forward
kubectl port-forward -n workers deployment/remediation-worker 8080:8080

# Send test alert
curl -X POST http://localhost:8080/webhook/alert \
  -H "Content-Type: application/json" \
  -d @test-alert.json

# Check metrics
curl http://localhost:8080/metrics | grep remediation
```

---

## Alert Flow

```
┌──────────────┐
│  Prometheus  │  (scrapes metrics)
└──────┬───────┘
       │ evaluates PrometheusRules
       ▼
┌──────────────────┐
│  Alertmanager    │  (routes alerts)
└──────┬───────────┘
       │
       ├─────► Slack (#alerts-critical, #alerts-warning)
       │
       └─────► Remediation Worker
               │
               ├─── Check rate limits & cooldowns
               ├─── Execute action (restart, scale, rollback)
               ├─── Record metrics
               └─── Send Slack notification
```

## Dashboards

### Grafana Dashboards

1. **EKS Cluster Overview** (`dashboard-eks-overview.json`)
   - Total nodes, pods, running/unhealthy pods
   - Node CPU and memory usage
   - Pods by namespace
   - Network traffic

2. **API Latency** (`dashboard-api-latency.json`)
   - P50, P95, P99 latency
   - Request rate by service
   - HTTP status distribution
   - Latency by endpoint

3. **JVM Metrics** (`dashboard-jvm-metrics.json`)
   - Heap and non-heap memory
   - GC pause frequency and duration
   - Thread count
   - Loaded classes

4. **GPU Metrics** (`dashboard-gpu-metrics.json`)
   - GPU utilization and memory
   - Temperature and power consumption
   - PCIe throughput
   - Clock speed

5. **Redis Metrics** (`dashboard-redis-metrics.json`)
   - Connected clients
   - Memory usage
   - Cache hit rate
   - Evicted/expired keys
   - Network I/O

6. **SQS Metrics** (`dashboard-sqs-metrics.json`)
   - Queue depth
   - In-flight messages
   - Message age
   - Throughput (sent/received/deleted)
   - DLQ messages

**Import Dashboards:**
```bash
# Method 1: Grafana UI
# - Go to Dashboards → Import
# - Paste JSON content or upload file

# Method 2: kubectl configmap
kubectl create configmap grafana-dashboards \
  -n monitoring \
  --from-file=monitoring/dashboard-eks-overview.json \
  --from-file=monitoring/dashboard-api-latency.json \
  --from-file=monitoring/dashboard-jvm-metrics.json \
  --from-file=monitoring/dashboard-gpu-metrics.json \
  --from-file=monitoring/dashboard-redis-metrics.json \
  --from-file=monitoring/dashboard-sqs-metrics.json

# Add annotation to configmap for auto-discovery
kubectl annotate configmap grafana-dashboards \
  -n monitoring \
  grafana_dashboard="1"
```

---

## Alerts

### Alert Severity Levels

- **Critical**: Immediate action required, service degraded
- **Warning**: Attention needed, potential future impact
- **Info**: Informational, no action required

### Alert Categories

1. **Backend API Alerts**
   - BackendHighErrorRate (5xx > 5%)
   - BackendHighLatency (P99 > 2s)
   - BackendPodRestarting
   - BackendDBPoolExhaustion (> 90%)
   - BackendHighMemoryUsage (> 90%)

2. **Service Alerts**
   - AgentServiceHighErrorRate
   - AgentServicePodRestarting
   - PostureAnalysisPodRestarting
   - ReportServiceHighErrorRate

3. **Infrastructure Alerts**
   - GPUHighUtilization (> 95%)
   - GPUMemoryHigh (> 90%)
   - RedisConnectionError
   - RedisHighMemory (> 90%)
   - RedisHighEvictionRate (> 100 keys/sec)
   - BedrockHighErrorRate (> 5%)
   - BedrockThrottling (> 10 req/sec)
   - SQSQueueBacklog (> 1000 messages)
   - SQSMessageAge (> 30 minutes)
   - SQSDLQMessages (> 10)

**Alert Routing:**
- **Critical alerts** → Slack #alerts-critical + Remediation Worker
- **Warning alerts** → Slack #alerts-warning + Remediation Worker
- **Info alerts** → Slack #alerts-info

---

## Operational Procedures

### Viewing Alerts

**Alertmanager UI:**
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093

# Open http://localhost:9093
```

**Slack:**
- #alerts-critical
- #alerts-warning
- #alerts-info

### Silencing Alerts

**Via Alertmanager UI:**
1. Go to http://localhost:9093
2. Click on alert
3. Click "Silence"
4. Set duration and reason

**Via CLI:**
```bash
amtool silence add alertname=BackendHighErrorRate --duration=1h --comment="Maintenance window"
```

### Disabling Auto-Remediation

**Globally (emergency):**
```bash
kubectl set env deployment/remediation-worker -n workers DRY_RUN=true
```

**Per-alert:**
Edit `alert-rules.yaml` and set `dryRun: true` for specific rule.

### Manual Remediation

**Restart service:**
```bash
kubectl rollout restart deployment/backend-api -n backend-api
```

**Scale service:**
```bash
kubectl scale deployment/backend-api -n backend-api --replicas=5
```

**Argo CD rollback:**
```bash
argocd app rollback backend-api-dev
```

---

## Metrics

### Key Metrics Endpoints

- **Prometheus**: `http://kube-prometheus-stack-prometheus.monitoring.svc:9090`
- **Alertmanager**: `http://kube-prometheus-stack-alertmanager.monitoring.svc:9093`
- **Grafana**: `http://kube-prometheus-stack-grafana.monitoring.svc:80`
- **Remediation Worker**: `http://remediation-worker.workers.svc:8080/metrics`

### Useful PromQL Queries

**Error rate:**
```promql
sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m])) by (namespace)
/ sum(rate(http_server_requests_seconds_count[5m])) by (namespace) * 100
```

**Latency P99:**
```promql
histogram_quantile(0.99, sum(rate(http_server_requests_seconds_bucket[5m])) by (le, namespace))
```

**Pod restarts:**
```promql
increase(kube_pod_container_status_restarts_total[1h]) > 0
```

**GPU utilization:**
```promql
DCGM_FI_DEV_GPU_UTIL{namespace="posture-analysis"}
```

**Redis memory:**
```promql
redis_memory_used_bytes / redis_memory_max_bytes * 100
```

**SQS queue depth:**
```promql
aws_sqs_approximate_number_of_messages_visible_average
```

---

## Troubleshooting

### Prometheus Not Scraping

1. Check ServiceMonitor exists:
   ```bash
   kubectl get servicemonitor -n <namespace>
   ```

2. Verify service has correct labels:
   ```bash
   kubectl get service <service-name> -n <namespace> -o yaml | grep -A 5 labels
   ```

3. Check Prometheus targets:
   ```bash
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
   # Open http://localhost:9090/targets
   ```

### Grafana Dashboard Not Showing Data

1. Verify Prometheus data source configured
2. Check query in Grafana's Explore view
3. Verify time range is correct
4. Check if metrics exist in Prometheus

### Alertmanager Not Sending Alerts

1. Check Alertmanager config:
   ```bash
   kubectl get secret -n monitoring kube-prometheus-stack-alertmanager -o yaml
   ```

2. Verify webhook URL is correct
3. Check Alertmanager logs:
   ```bash
   kubectl logs -n monitoring statefulset/alertmanager-kube-prometheus-stack-alertmanager
   ```

### Remediation Worker Not Acting

1. Check dry-run mode:
   ```bash
   kubectl get deployment remediation-worker -n workers -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="DRY_RUN")].value}'
   ```

2. View logs:
   ```bash
   kubectl logs -n workers deployment/remediation-worker --tail=100
   ```

3. Check alert-rules ConfigMap:
   ```bash
   kubectl get configmap alert-rules -n workers -o yaml
   ```

4. Verify secrets exist:
   ```bash
   kubectl get secret remediation-secrets -n workers
   ```

---

## Cost Optimization

### CloudWatch Logs

- Set appropriate retention periods (7 days dev, 30 days prod)
- Export to S3 for long-term archival
- Use Athena partitions to reduce scan costs

### Prometheus Storage

- Configure retention period: 7 days dev, 30 days prod
- Use remote write to long-term storage (Thanos, Cortex) if needed
- Enable metric relabeling to drop unused metrics

### Grafana

- Limit dashboard refresh rates
- Use caching for frequently accessed dashboards
- Disable unused datasources
- Keep Athena panels scoped by partition/time filters to avoid broad S3 scans

---

## Security

### RBAC

All services use Kubernetes ServiceAccounts with least-privilege RBAC:
- Prometheus: Read-only access to pods, services, endpoints
- Remediation Worker: Edit access to deployments in specific namespaces

### IRSA

AWS permissions via IAM Roles for Service Accounts:
- Prometheus CloudWatch exporter: CloudWatch read
- Fluent Bit: CloudWatch Logs write
- Remediation Worker: EKS describe

### Secrets Management

- Slack webhook URLs: Kubernetes Secrets
- Argo CD tokens: Kubernetes Secrets
- Never commit secrets to Git

---

## Maintenance

### Updating kube-prometheus-stack

```bash
helm repo update
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f values-dev.yaml
```

### Updating Remediation Worker

```bash
# Build new image
docker build -t <ECR_REPO>/remediation-worker:v1.1.0 .
docker push <ECR_REPO>/remediation-worker:v1.1.0

# Update deployment
kubectl set image deployment/remediation-worker \
  -n workers \
  remediation-worker=<ECR_REPO>/remediation-worker:v1.1.0
```

### Backup and Restore

**Grafana Dashboards:**
```bash
# Export
kubectl get configmap grafana-dashboards -n monitoring -o yaml > dashboards-backup.yaml

# Restore
kubectl apply -f dashboards-backup.yaml
```

**Prometheus Data:**
Use Prometheus snapshots or remote write to long-term storage.

---

## References

- [kube-prometheus-stack Documentation](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Prometheus Operator Documentation](https://prometheus-operator.dev/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Alertmanager Documentation](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [Fluent Bit Documentation](https://docs.fluentbit.io/)
- [CloudWatch Logs Insights Query Syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)
- [Athena SQL Reference](https://docs.aws.amazon.com/athena/latest/ug/ddl-sql-reference.html)
- [Remediation Worker README](../../gympt-app/remediation-worker/README.md)
- [Runbooks](./remediation/runbooks.md)

---

**Last Updated:** 2026-06-08
**Maintainer:** Platform Team
