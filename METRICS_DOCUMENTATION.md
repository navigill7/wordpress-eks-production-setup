# Monitoring & Metrics

## Architecture

See the monitoring stack diagram here:

The flow is:
- ServiceMonitor finds pods to scrape
- Prometheus scrapes /metrics from nginx and cAdvisor from kubelets
- Data goes to Grafana (dashboards) and AlertManager (alerts)

## What's Running

The monitoring namespace has:
- Prometheus - collects and stores metrics
- Grafana - shows dashboards
- AlertManager - sends alerts
- ServiceMonitor - finds services to scrape

## Nginx Metrics

Custom Lua script exposes metrics at `/metrics`

**nginx_requests_total** - total requests handled

```promql
nginx_requests_total                    # current count
rate(nginx_requests_total[5m])          # requests per second
increase(nginx_requests_total[1h])      # requests last hour
```

Implementation is in `docker/nginx-openresty/lua/metrics.lua`

## CPU Metrics

From cAdvisor (runs on every node):

**container_cpu_usage_seconds_total** - CPU time used

```promql
# per pod rate
rate(container_cpu_usage_seconds_total{pod=~"wordpress.*|nginx.*|mysql.*"}[5m])

# grouped by pod
sum(rate(container_cpu_usage_seconds_total{pod=~"wordpress.*|nginx.*|mysql.*",container!=""}[5m])) by (pod)

# as percentage of limit
rate(container_cpu_usage_seconds_total[5m]) / on(pod) group_left() kube_pod_container_resource_limits{resource="cpu"}
```

## Memory Metrics

**container_memory_usage_bytes** - current memory
**container_spec_memory_limit_bytes** - memory limit

```promql
# raw usage
container_memory_usage_bytes{pod=~"wordpress.*|nginx.*|mysql.*",container!=""}

# grouped
sum(container_memory_usage_bytes{pod=~"wordpress.*|nginx.*|mysql.*",container!=""}) by (pod)

# percentage
(container_memory_usage_bytes / container_spec_memory_limit_bytes) * 100
```

## Network Metrics

**container_network_receive_bytes_total** - bytes in
**container_network_transmit_bytes_total** - bytes out

```promql
# incoming rate
rate(container_network_receive_bytes_total{pod=~"wordpress.*"}[5m])

# outgoing rate  
rate(container_network_transmit_bytes_total{pod=~"wordpress.*"}[5m])

# total bandwidth
sum(rate(container_network_receive_bytes_total[5m]) + rate(container_network_transmit_bytes_total[5m])) by (pod)
```

## Disk I/O

**container_fs_reads_bytes_total** - disk reads
**container_fs_writes_bytes_total** - disk writes

```promql
rate(container_fs_reads_bytes_total{pod=~"mysql.*"}[5m])
rate(container_fs_writes_bytes_total{pod=~"mysql.*"}[5m])
```

## Pod Status

**kube_pod_status_phase** - pod state
**kube_pod_container_status_restarts_total** - restart count

```promql
kube_pod_status_phase{pod=~"wordpress.*|nginx.*|mysql.*"}
kube_pod_container_status_restarts_total{pod=~"wordpress.*"}
```

## Checking Metrics

Access Prometheus:
```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
```
Open http://localhost:9090

Query examples:
- Go to Graph tab
- Enter query
- Click Execute

Access Grafana:
```bash
kubectl get svc -n monitoring prometheus-grafana
```
Login: admin / admin123

## Custom Dashboard Setup

Create new dashboard in Grafana:

**Panel 1: Request Rate**
- Query: `rate(nginx_requests_total[5m])`
- Type: Graph
- Unit: req/s

**Panel 2: Pod CPU**
- Query: `sum(rate(container_cpu_usage_seconds_total{pod=~"wordpress.*|nginx.*|mysql.*",container!=""}[5m])) by (pod)`
- Type: Graph
- Legend: {{pod}}

**Panel 3: Pod Memory**
- Query: `sum(container_memory_usage_bytes{pod=~"wordpress.*|nginx.*|mysql.*",container!=""}) by (pod)`
- Type: Graph
- Unit: bytes

**Panel 4: Network I/O**
- Query: `rate(container_network_receive_bytes_total{pod=~"wordpress.*"}[5m])`
- Type: Graph
- Unit: Bps

## Alert Examples

CPU high:
```yaml
- alert: HighCPU
  expr: rate(container_cpu_usage_seconds_total[5m]) > 0.8
  for: 5m
  annotations:
    summary: "Pod {{ $labels.pod }} high CPU"
```

Memory high:
```yaml
- alert: HighMemory
  expr: (container_memory_usage_bytes / container_spec_memory_limit_bytes) > 0.9
  for: 5m
  annotations:
    summary: "Pod {{ $labels.pod }} high memory"
```

Pod restarts:
```yaml
- alert: PodRestarting
  expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
  annotations:
    summary: "Pod {{ $labels.pod }} restarting"
```

## Debugging

Check if ServiceMonitor is working:
```bash
kubectl get servicemonitor -n monitoring
kubectl describe servicemonitor nginx-metrics -n monitoring
```

Check Prometheus targets:
```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
```
Open http://localhost:9090/targets

View Prometheus logs:
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus --tail=100
```

Test nginx metrics directly:
```bash
NGINX_URL=$(kubectl get svc nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$NGINX_URL/metrics
```

## Useful Queries

WordPress response time (if instrumented):
```promql
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

MySQL connections (if mysqld_exporter added):
```promql
mysql_global_status_threads_connected
```

EFS throughput:
```promql
sum(rate(container_fs_reads_bytes_total{mountpoint=~".*efs.*"}[5m])) by (pod)
```

Node resource usage:
```promql
sum(rate(node_cpu_seconds_total{mode!="idle"}[5m])) by (instance)
sum(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) by (instance)
```