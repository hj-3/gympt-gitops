# Logging Platform

## Overview

The GYMPT logging infrastructure uses a multi-tier approach:

1. **Container Logs** → CloudWatch Log Groups (via Fluent Bit)
2. **CloudWatch Logs** → S3 (export for archival)
3. **S3 Logs** → Athena (query and analysis)

## Architecture

```
┌─────────────┐
│   EKS Pods  │
└──────┬──────┘
       │ stdout/stderr
       ▼
┌─────────────┐
│ Fluent Bit  │ (DaemonSet)
└──────┬──────┘
       │
       ▼
┌──────────────────┐
│ CloudWatch Logs  │
│  Log Groups:     │
│  - /aws/eks/gympt-dev-eks/backend-api
│  - /aws/eks/gympt-dev-eks/agent-service
│  - /aws/eks/gympt-dev-eks/posture-analysis
│  - /aws/eks/gympt-dev-eks/report-service
│  - /aws/eks/gympt-dev-eks/workers
└──────┬───────────┘
       │
       ├─────► Real-time Metrics (via Subscription Filters)
       │
       └─────► S3 Export (daily)
               │
               ▼
         ┌────────────┐
         │  S3 Bucket │
         │  gympt-dev-logs
         └─────┬──────┘
               │
               ▼
         ┌────────────┐
         │   Athena   │ (SQL queries)
         └────────────┘
```

## CloudWatch Log Groups

### Naming Convention

```
/aws/eks/{cluster-name}/{namespace}
```

Example:
- `/aws/eks/gympt-dev-eks/backend-api`
- `/aws/eks/gympt-dev-eks/agent-service`

### Retention

- **Dev**: 7 days
- **Prod**: 30 days

### Log Format

All application logs should use **structured JSON** format:

```json
{
  "timestamp": "2026-05-19T10:30:00.000Z",
  "level": "INFO",
  "logger": "com.gympt.api.UserController",
  "message": "User login successful",
  "userId": "user-123",
  "requestId": "req-abc-xyz",
  "traceId": "trace-def-456"
}
```

## Fluent Bit Configuration

Fluent Bit runs as a DaemonSet in the `kube-system` namespace and automatically collects logs from all pods.

### Optional: Enhanced Fluent Bit

If you need custom log parsing or filtering, see `fluent-bit-values.yaml` for advanced configuration.

Basic Fluent Bit is installed by default via EKS add-on.

## Athena Queries

### Athena Table Schema

The Glue Crawler (defined in Terraform `modules/glue`) automatically creates Athena tables from S3 logs.

Database: `gympt_logs`

Tables:
- `backend_api`
- `agent_service`
- `posture_analysis`
- `report_service`
- `workers`

### Example Queries

**1. Find all ERROR logs in the last 24 hours:**

```sql
SELECT timestamp, level, message, logger, userId
FROM backend_api
WHERE level = 'ERROR'
  AND timestamp >= NOW() - INTERVAL '24' HOUR
ORDER BY timestamp DESC
LIMIT 100;
```

**2. Count errors by service:**

```sql
SELECT logger, COUNT(*) as error_count
FROM backend_api
WHERE level = 'ERROR'
  AND timestamp >= NOW() - INTERVAL '7' DAY
GROUP BY logger
ORDER BY error_count DESC;
```

**3. Find slow requests (>2s):**

```sql
SELECT timestamp, message, requestId, duration_ms
FROM backend_api
WHERE message LIKE '%request completed%'
  AND CAST(json_extract_scalar(message, '$.duration_ms') AS DOUBLE) > 2000
  AND timestamp >= NOW() - INTERVAL '1' HOUR
ORDER BY timestamp DESC;
```

**4. Trace a specific request across services:**

```sql
-- Backend API
SELECT 'backend-api' as service, timestamp, level, message
FROM backend_api
WHERE requestId = 'req-abc-xyz'

UNION ALL

-- Agent Service
SELECT 'agent-service' as service, timestamp, level, message
FROM agent_service
WHERE requestId = 'req-abc-xyz'

ORDER BY timestamp ASC;
```

**5. Monitor GPU service errors:**

```sql
SELECT timestamp, level, message, pod_name
FROM posture_analysis
WHERE level IN ('ERROR', 'WARN')
  AND timestamp >= NOW() - INTERVAL '1' HOUR
ORDER BY timestamp DESC;
```

## CloudWatch Insights Queries

For real-time queries directly in CloudWatch (without waiting for S3 export):

### 1. Error Rate Over Time

```
fields @timestamp, @message
| filter level = "ERROR"
| stats count() as error_count by bin(5m)
```

### 2. Top Error Messages

```
fields @timestamp, message
| filter level = "ERROR"
| stats count() as count by message
| sort count desc
| limit 20
```

### 3. Latency Analysis

```
fields @timestamp, duration_ms
| filter message like /request completed/
| stats avg(duration_ms) as avg_latency, pct(duration_ms, 95) as p95_latency, pct(duration_ms, 99) as p99_latency by bin(5m)
```

### 4. Filter by User

```
fields @timestamp, level, message
| filter userId = "user-123"
| sort @timestamp desc
| limit 100
```

## Log Retention and Cost Optimization

### CloudWatch Logs Costs

- **Ingestion**: $0.50 per GB
- **Storage**: $0.03 per GB/month
- **Data transfer**: Free to S3 in same region

### Athena Costs

- **Queries**: $5.00 per TB scanned
- **Storage in S3**: $0.023 per GB/month (Standard)

### Best Practices

1. **Use structured JSON** for efficient querying
2. **Set appropriate retention periods** (7 days dev, 30 days prod)
3. **Export to S3** for long-term archival and Athena analysis
4. **Use Glue partitions** (Terraform module already configured) to reduce Athena scan costs
5. **Filter early** in queries to minimize data scanned

## Operational Procedures

### View Recent Logs for a Service

**CLI:**

```bash
aws logs tail /aws/eks/gympt-dev-eks/backend-api --follow --region ap-northeast-2
```

**Console:**
CloudWatch → Log groups → `/aws/eks/gympt-dev-eks/backend-api` → Log streams

### Search Logs Across All Services

**CloudWatch Insights:**

1. Go to CloudWatch → Insights
2. Select multiple log groups
3. Run query (see examples above)

### Export Logs to S3 (Manual)

```bash
aws logs create-export-task \
  --log-group-name /aws/eks/gympt-dev-eks/backend-api \
  --from 1621000000000 \
  --to 1621086400000 \
  --destination gympt-dev-logs-<account-id> \
  --destination-prefix manual-export/ \
  --region ap-northeast-2
```

### Query Historical Logs with Athena

1. Open Athena console
2. Select database: `gympt_logs`
3. Run SQL query (see examples above)
4. Results appear in S3: `gympt-dev-athena-results-<account-id>`

## Troubleshooting

### Logs Not Appearing in CloudWatch

1. **Check Fluent Bit DaemonSet:**

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-for-fluent-bit
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-for-fluent-bit --tail=100
```

2. **Verify IAM permissions** for Fluent Bit service account (IRSA)

3. **Check log group exists:**

```bash
aws logs describe-log-groups --log-group-name-prefix /aws/eks/gympt-dev-eks --region ap-northeast-2
```

### Athena Table Not Found

1. **Run Glue Crawler manually:**

```bash
aws glue start-crawler --name gympt-dev-logs-crawler --region ap-northeast-2
```

2. **Check S3 bucket** has exported logs

3. **Verify table exists:**

```bash
aws glue get-table --database-name gympt_logs --name backend_api --region ap-northeast-2
```

### High CloudWatch Costs

1. **Review log volume by service:**

```bash
aws logs describe-log-groups --region ap-northeast-2 | jq '.logGroups[] | {name: .logGroupName, storedBytes: .storedBytes}'
```

2. **Reduce retention period** for non-critical services
3. **Filter verbose debug logs** at application level
4. **Use sampling** for high-volume trace logs

## Integration with Monitoring

CloudWatch Logs integrate with the monitoring platform:

1. **Log-based metrics** can trigger CloudWatch Alarms
2. **Subscription filters** can forward specific log patterns to Lambda or Kinesis
3. **Prometheus** can scrape CloudWatch Logs metrics via `cloudwatch_exporter`

Example: Create alarm for ERROR log rate:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name backend-api-high-error-rate \
  --metric-name ErrorCount \
  --namespace AWS/Logs \
  --statistic Sum \
  --period 300 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions <SNS-TOPIC-ARN>
```

## References

- [Fluent Bit Documentation](https://docs.fluentbit.io/)
- [CloudWatch Logs Insights Query Syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)
- [Athena SQL Reference](https://docs.aws.amazon.com/athena/latest/ug/ddl-sql-reference.html)
- [Terraform Glue Module](../../terraform/modules/glue/)
- [Terraform CloudWatch Module](../../terraform/modules/cloudwatch/)
