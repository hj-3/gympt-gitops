# Remediation Runbooks

This document contains operational runbooks for alerts and automated remediation actions.

---

## Table of Contents

1. [Backend API Alerts](#backend-api-alerts)
2. [Agent Service Alerts](#agent-service-alerts)
3. [Posture Analysis Alerts](#posture-analysis-alerts)
4. [Report Service Alerts](#report-service-alerts)
5. [Infrastructure Alerts](#infrastructure-alerts)
6. [Manual Remediation Procedures](#manual-remediation-procedures)
7. [Disabling Auto-Remediation](#disabling-auto-remediation)

---

## Backend API Alerts

### BackendHighErrorRate

**Alert**: 5xx error rate > 5% for 5 minutes

**Automated Action**: Restart deployment

**Manual Steps** (if auto-remediation fails):

1. Check recent deployments:
   ```bash
   kubectl rollout history deployment/backend-api -n backend-api
   ```

2. View error logs:
   ```bash
   kubectl logs -n backend-api -l app=backend-api --tail=100 | grep ERROR
   ```

3. Check database connectivity:
   ```bash
   kubectl exec -n backend-api deployment/backend-api -- curl -s http://localhost:8080/actuator/health
   ```

4. Manual rollback if needed:
   ```bash
   kubectl rollout undo deployment/backend-api -n backend-api
   ```

5. If persistent, check:
   - RDS instance status in AWS console
   - Redis connection (ElastiCache)
   - Network policies
   - Recent schema migrations

---

### BackendHighLatency

**Alert**: P99 latency > 2s for 10 minutes

**Automated Action**: Scale up deployment (+1 replica)

**Manual Steps**:

1. Check current pod status:
   ```bash
   kubectl get pods -n backend-api
   kubectl top pods -n backend-api
   ```

2. Review slow queries in logs:
   ```bash
   kubectl logs -n backend-api -l app=backend-api | grep "slow query"
   ```

3. Check database connection pool:
   ```bash
   kubectl exec -n backend-api deployment/backend-api -- curl -s http://localhost:8080/actuator/metrics/hikaricp.connections.active
   ```

4. Analyze with CloudWatch Insights:
   ```
   fields @timestamp, duration_ms
   | filter message like /request completed/
   | stats avg(duration_ms), pct(duration_ms, 99) by bin(5m)
   ```

5. Consider:
   - Database query optimization
   - Adding database indexes
   - Increasing RDS instance size
   - Enabling query caching

---

### BackendPodRestarting

**Alert**: Pod has restarted in the last 10 minutes

**Automated Action**: Rollback via Argo CD

**Manual Steps**:

1. Check pod restart reason:
   ```bash
   kubectl describe pod -n backend-api -l app=backend-api | grep -A 10 "Last State"
   ```

2. View exit code and logs:
   ```bash
   kubectl logs -n backend-api -l app=backend-api --previous
   ```

3. Common causes:
   - **OOMKilled**: Increase memory limits
   - **CrashLoopBackOff**: Check application startup logs
   - **Liveness probe failure**: Review probe configuration
   - **Node eviction**: Check node resources

4. Manual Argo CD rollback:
   ```bash
   argocd app rollback backend-api-dev
   ```

5. If persistent:
   - Review recent code changes
   - Check for resource exhaustion (CPU, memory)
   - Verify environment variables and secrets

---

### BackendDBPoolExhaustion

**Alert**: DB connection pool > 90% for 5 minutes

**Automated Action**: Restart deployment

**Manual Steps**:

1. Check current pool metrics:
   ```bash
   kubectl exec -n backend-api deployment/backend-api -- curl -s http://localhost:8080/actuator/metrics/hikaricp.connections | jq .
   ```

2. Identify long-running queries:
   ```sql
   -- Run in RDS PostgreSQL
   SELECT pid, now() - pg_stat_activity.query_start AS duration, query, state
   FROM pg_stat_activity
   WHERE state != 'idle'
   ORDER BY duration DESC;
   ```

3. Kill long-running queries if needed:
   ```sql
   SELECT pg_terminate_backend(pid);
   ```

4. Review connection pool configuration in `application.yml`:
   ```yaml
   spring:
     datasource:
       hikari:
         maximum-pool-size: 20
         connection-timeout: 30000
   ```

5. Consider:
   - Increasing pool size
   - Implementing connection timeout
   - Adding query timeout
   - Using read replicas for read-heavy queries

---

### BackendHighMemoryUsage

**Alert**: JVM heap memory > 90% for 10 minutes

**Automated Action**: Restart deployment

**Manual Steps**:

1. Capture heap dump before restart:
   ```bash
   kubectl exec -n backend-api deployment/backend-api -- jmap -dump:format=b,file=/tmp/heap.hprof 1
   kubectl cp backend-api/backend-api-xxx:/tmp/heap.hprof ./heap.hprof
   ```

2. Analyze with tools like:
   - Eclipse MAT (Memory Analyzer Tool)
   - VisualVM
   - JProfiler

3. Check for memory leaks:
   ```bash
   kubectl exec -n backend-api deployment/backend-api -- jmap -histo:live 1 | head -30
   ```

4. Review GC metrics:
   ```bash
   kubectl exec -n backend-api deployment/backend-api -- curl -s http://localhost:8080/actuator/metrics/jvm.gc.pause | jq .
   ```

5. Consider:
   - Increasing heap size in deployment
   - Investigating code for memory leaks
   - Optimizing data structures
   - Implementing caching strategies

---

## Agent Service Alerts

### AgentServiceHighErrorRate

**Alert**: 5xx error rate > 5% for 5 minutes

**Automated Action**: Restart deployment

**Manual Steps**: Similar to BackendHighErrorRate, but check:
- Bedrock API connectivity
- S3 bucket access (for AI model artifacts)
- GPU node availability

---

### AgentServicePodRestarting

**Alert**: Pod restarting

**Automated Action**: Rollback via Argo CD

**Manual Steps**: Similar to BackendPodRestarting, additionally check:
- Bedrock API rate limits
- GPU resource availability
- CUDA errors in logs

---

## Posture Analysis Alerts

### PostureAnalysisPodRestarting

**Alert**: GPU service pod restarting

**Automated Action**: Rollback via Argo CD

**Manual Steps**:

1. Check GPU node status:
   ```bash
   kubectl get nodes -l node.kubernetes.io/instance-type=g4dn.xlarge
   kubectl describe node <gpu-node-name>
   ```

2. Check GPU availability:
   ```bash
   kubectl get pods -n posture-analysis -o wide
   kubectl describe pod -n posture-analysis <pod-name> | grep -A 5 "nvidia.com/gpu"
   ```

3. View GPU metrics:
   ```bash
   nvidia-smi
   ```

4. Common GPU issues:
   - **GPU not found**: NVIDIA device plugin not running
   - **CUDA error**: Driver version mismatch
   - **OOM**: GPU memory exhausted

5. Check NVIDIA device plugin:
   ```bash
   kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds
   ```

---

## Report Service Alerts

### ReportServiceHighErrorRate

**Alert**: 5xx error rate > 5% for 5 minutes

**Automated Action**: Restart deployment

**Manual Steps**: Check:
- S3 bucket permissions
- DynamoDB table access
- Lambda function invocation errors (if used)

---

## Infrastructure Alerts

### GPUHighUtilization

**Alert**: GPU utilization > 95% for 10 minutes

**Automated Action**: Notify only (manual scaling required)

**Manual Steps**:

1. Check GPU workload distribution:
   ```bash
   kubectl top pods -n posture-analysis
   ```

2. Scale GPU node group:
   ```bash
   aws eks update-nodegroup-config \
     --cluster-name gympt-dev-eks \
     --nodegroup-name gympt-dev-gpu-nodes \
     --scaling-config minSize=1,maxSize=5,desiredSize=2 \
     --region ap-northeast-2
   ```

3. Consider:
   - Implementing request queuing
   - Optimizing model inference
   - Batch processing

---

### RedisConnectionError

**Alert**: Zero Redis connections for 2 minutes

**Automated Action**: Notify only

**Manual Steps**:

1. Check ElastiCache cluster status:
   ```bash
   aws elasticache describe-cache-clusters \
     --cache-cluster-id gympt-dev-redis \
     --region ap-northeast-2
   ```

2. Test connectivity from pod:
   ```bash
   kubectl run -it --rm redis-test --image=redis --restart=Never -- redis-cli -h <redis-endpoint> PING
   ```

3. Check security groups:
   ```bash
   aws ec2 describe-security-groups \
     --group-ids <redis-sg-id> \
     --region ap-northeast-2
   ```

4. Common causes:
   - ElastiCache maintenance window
   - Security group misconfiguration
   - Network connectivity issue
   - ElastiCache failover

---

### SQSQueueBacklog

**Alert**: Queue has > 1000 messages for 10 minutes

**Automated Action**: Scale up worker deployment (+2 replicas)

**Manual Steps**:

1. Check queue depth:
   ```bash
   aws sqs get-queue-attributes \
     --queue-url <queue-url> \
     --attribute-names ApproximateNumberOfMessages \
     --region ap-northeast-2
   ```

2. View DLQ messages:
   ```bash
   aws sqs receive-message \
     --queue-url <dlq-url> \
     --max-number-of-messages 10 \
     --region ap-northeast-2
   ```

3. Check worker health:
   ```bash
   kubectl get pods -n workers
   kubectl logs -n workers -l app=generic-worker --tail=50
   ```

4. Consider:
   - Increasing worker replicas further
   - Investigating slow message processing
   - Purging old messages if no longer relevant

---

## Manual Remediation Procedures

### Force Restart a Service

```bash
kubectl rollout restart deployment/<deployment-name> -n <namespace>
```

### Manual Scale

```bash
kubectl scale deployment/<deployment-name> -n <namespace> --replicas=<count>
```

### Manual Argo CD Sync

```bash
argocd app sync <application-name> --force
```

### Manual Argo CD Rollback

```bash
argocd app rollback <application-name> <revision-id>
```

### View Argo CD History

```bash
argocd app history <application-name>
```

### Emergency Pod Deletion

```bash
kubectl delete pod <pod-name> -n <namespace> --grace-period=0 --force
```

---

## Disabling Auto-Remediation

### Disable Globally (Emergency)

Set environment variable in remediation-worker:

```bash
kubectl set env deployment/remediation-worker -n workers DRY_RUN=true
```

### Disable for Specific Alert

Edit `alert-rules.yaml` and set `dryRun: true` for the specific rule:

```yaml
- alertName: BackendHighErrorRate
  severity: critical
  action: restart_deployment
  dryRun: true  # <-- Set to true
  notifySlack: true
```

Then update the ConfigMap:

```bash
kubectl apply -f alert-rules.yaml
kubectl rollout restart deployment/remediation-worker -n workers
```

### Exclude a Deployment

Add to `values-dev.yaml`:

```yaml
excludedDeployments:
  - my-critical-deployment
```

---

## Monitoring Remediation Actions

### View remediation-worker logs:

```bash
kubectl logs -n workers deployment/remediation-worker --follow
```

### Check remediation metrics:

```bash
kubectl port-forward -n workers deployment/remediation-worker 8080:8080

# In another terminal
curl http://localhost:8080/metrics | grep remediation
```

### Slack notifications:

All auto-remediation actions are posted to `#alerts-critical` and `#alerts-warning` Slack channels.

---

## Rollback Procedure for Failed Auto-Remediation

1. **Identify the failed action** from logs or Slack notification

2. **Check deployment status**:
   ```bash
   kubectl get deployment -n <namespace> <deployment-name>
   kubectl rollout status deployment/<deployment-name> -n <namespace>
   ```

3. **Rollback to previous state**:
   ```bash
   kubectl rollout undo deployment/<deployment-name> -n <namespace>
   ```

4. **Disable auto-remediation** for that alert (see above)

5. **Investigate root cause** before re-enabling

---

## Contact

For questions or incidents related to auto-remediation:
- **Slack**: #platform-team
- **PagerDuty**: Platform Engineering on-call
- **Email**: platform-team@gympt.com

## References

- [Prometheus Alerts](../monitoring/prometheusrule-backend.yaml)
- [Alert Rules](./alert-rules.yaml)
- [Helm Values](./values-dev.yaml)
- [Kubernetes Troubleshooting Guide](https://kubernetes.io/docs/tasks/debug/)
- [Argo CD Rollback Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/commands/argocd_app_rollback/)
