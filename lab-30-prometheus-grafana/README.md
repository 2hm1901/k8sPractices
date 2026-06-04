# Lab 30 — Metrics với Prometheus & Grafana

## 🎯 Mục tiêu (Objectives)

Sau lab này, bạn sẽ hiểu và thực hành được:
- Prometheus data model và 4 loại metrics: Counter, Gauge, Histogram, Summary
- Scraping pull model so với push model
- Cài đặt `kube-prometheus-stack` qua Helm (bao gồm Prometheus, Grafana, AlertManager)
- Tạo `ServiceMonitor` và `PodMonitor` CRDs để scrape custom apps
- Viết PromQL queries cơ bản: `rate()`, `sum()`, `by()`, `histogram_quantile()`
- Cấu hình AlertManager rules và routing
- Import và tạo Grafana dashboards
- Expose custom `/metrics` endpoint từ ứng dụng

---

## 📋 Prerequisites

- Hoàn thành Lab 29 (hiểu observability concepts)
- `kubectl` kết nối được với cluster
- **Helm 3** đã cài đặt (bắt buộc cho lab này)
- Cluster có ít nhất **6GB RAM** khả dụng
- Kết nối internet để pull Helm charts

```bash
# Kiểm tra Helm
helm version --short

# Thêm Prometheus community Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Kiểm tra chart available
helm search repo prometheus-community/kube-prometheus-stack
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Prometheus Data Model

Mỗi metric là một **time series** được xác định bởi tên metric và tập hợp labels:

```
http_requests_total{method="GET", endpoint="/api/v1/users", status="200"} 1024 @timestamp
```

```
metric_name{label_key="label_value", ...}  <float64 value>  [timestamp_ms]
```

### 4 Loại Metrics Types

| Type | Mô tả | Ví dụ |
|------|--------|-------|
| **Counter** | Chỉ tăng, không giảm (reset khi restart) | `http_requests_total`, `errors_total` |
| **Gauge** | Tăng/giảm tùy ý | `memory_usage_bytes`, `active_connections` |
| **Histogram** | Phân phối giá trị vào buckets | `http_request_duration_seconds` |
| **Summary** | Tính quantile phía client | `rpc_duration_seconds{quantile="0.99"}` |

```
# Counter example:
# Chỉ dùng rate() với counter vì nó luôn tăng
http_requests_total{job="api-server"} 1234567

# Gauge example:
# Giá trị hiện tại tại thời điểm scrape
node_memory_MemAvailable_bytes 4294967296

# Histogram example:
# Generates 3 series: _bucket, _count, _sum
http_request_duration_seconds_bucket{le="0.1"} 800
http_request_duration_seconds_bucket{le="0.5"} 950
http_request_duration_seconds_bucket{le="1.0"} 980
http_request_duration_seconds_bucket{le="+Inf"} 1000
http_request_duration_seconds_count 1000
http_request_duration_seconds_sum 312.5
```

### Scraping Pull Model

```
┌─────────────────────────────────────────────────────────┐
│                      Prometheus                          │
│                                                          │
│  scrape_configs:                                         │
│    - job_name: 'kubernetes-pods'          ←─────────────┼──┐
│      kubernetes_sd_configs:               pull every 15s │  │
│                                                          │  │
└─────────────────────────────────────────────────────────┘  │
         │ discovers targets via K8s API                      │
         ▼                                                    │
┌─────────────────────────────────────────────────────────┐  │
│  Pod A (app + metrics sidecar)                          │  │
│  Exposes GET /metrics on port 8080                      │──┘
│  Content-Type: text/plain; version=0.0.4                │
└─────────────────────────────────────────────────────────┘
```

**Vs Push Model (Pushgateway)**: Dùng khi jobs ngắn (batch jobs) không thể bị scrape.

### kube-prometheus-stack Components

```
kube-prometheus-stack Helm Chart
├── Prometheus Operator        ← Manages Prometheus instances as CRDs
├── Prometheus                 ← Metrics collection and storage (TSDB)
├── Alertmanager               ← Alert routing (email, Slack, PagerDuty)
├── Grafana                    ← Visualization dashboards
├── kube-state-metrics         ← K8s object metrics (deployments, pods...)
├── node-exporter (DaemonSet)  ← Node-level metrics (CPU, memory, disk)
└── CRDs:
    ├── ServiceMonitor         ← Scrape config for Services
    ├── PodMonitor             ← Scrape config for Pods directly
    ├── PrometheusRule         ← Alert and recording rules
    └── AlertmanagerConfig     ← Alertmanager routing config
```

### PromQL Cơ Bản

```promql
# --- COUNTER queries (luôn dùng rate/irate) ---

# Request rate per second (5m window)
rate(http_requests_total[5m])

# Total request rate across all pods, grouped by endpoint
sum(rate(http_requests_total[5m])) by (endpoint)

# Error rate percentage
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) * 100

# --- GAUGE queries ---

# Memory usage in GiB
node_memory_MemAvailable_bytes / 1024^3

# CPU usage percentage
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# --- HISTOGRAM queries ---

# P99 latency (99th percentile)
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, endpoint))

# P50 (median) latency
histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))

# Average latency
rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m])

# --- KUBERNETES specific ---

# Pod restart count
sum(kube_pod_container_status_restarts_total) by (namespace, pod)

# Deployment unavailable replicas
kube_deployment_status_replicas_unavailable > 0

# Node not ready
kube_node_status_condition{condition="Ready",status="true"} == 0
```

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Tạo Namespace

```bash
kubectl apply -f manifests/namespace-monitoring.yaml
```

### Step 2: Cài đặt kube-prometheus-stack qua Helm

```bash
# Cài đặt với custom values
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values manifests/prometheus-values.yaml \
  --wait \
  --timeout 10m

# Kiểm tra installation
helm list -n monitoring
kubectl get pods -n monitoring
```

Chờ tất cả pods ready (~3-5 phút):
```bash
kubectl get pods -n monitoring -w
# Cần thấy: prometheus-*, grafana-*, alertmanager-*, kube-state-metrics-*, node-exporter-*
```

### Step 3: Truy cập Prometheus UI

```bash
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring &

# Mở browser: http://localhost:9090
# Targets: http://localhost:9090/targets (phải thấy tất cả targets UP)
```

Thử một số PromQL queries:
```promql
# Trong Prometheus UI → Graph tab
up
kube_pod_info
sum(rate(http_requests_total[5m])) by (namespace)
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))
```

### Step 4: Truy cập Grafana

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring &

# Mở browser: http://localhost:3000
# Credentials mặc định (từ values.yaml):
# Username: admin
# Password: admin123
```

Khám phá pre-built dashboards:
- **Kubernetes / Nodes** - CPU, Memory, Disk per node
- **Kubernetes / Pods** - Resource usage per pod
- **Kubernetes / Deployments** - Deployment health

### Step 5: Deploy Custom Metrics App

```bash
kubectl apply -f manifests/deployment-metrics-app.yaml
```

Xem app đang expose metrics gì:
```bash
kubectl port-forward svc/metrics-app 8080:8080 &
curl http://localhost:8080/metrics
```

Output ví dụ:
```
# HELP demo_requests_total Total number of requests processed
# TYPE demo_requests_total counter
demo_requests_total{endpoint="/api/users",method="GET",status="200"} 42
demo_requests_total{endpoint="/api/orders",method="POST",status="201"} 15
demo_requests_total{endpoint="/api/products",method="GET",status="500"} 3

# HELP demo_request_duration_seconds Request processing time in seconds
# TYPE demo_request_duration_seconds histogram
demo_request_duration_seconds_bucket{endpoint="/api/users",le="0.01"} 10
demo_request_duration_seconds_bucket{endpoint="/api/users",le="0.05"} 35
demo_request_duration_seconds_bucket{endpoint="/api/users",le="0.1"} 40
demo_request_duration_seconds_bucket{endpoint="/api/users",le="+Inf"} 42
demo_request_duration_seconds_sum{endpoint="/api/users"} 1.85
demo_request_duration_seconds_count{endpoint="/api/users"} 42

# HELP demo_active_connections Current number of active connections
# TYPE demo_active_connections gauge
demo_active_connections 7
```

### Step 6: Tạo ServiceMonitor để scrape custom app

```bash
kubectl apply -f manifests/servicemonitor-app.yaml

# Kiểm tra ServiceMonitor được tạo
kubectl get servicemonitor -n monitoring

# Trong vài phút, Prometheus sẽ tự động discover target mới
# Kiểm tra: http://localhost:9090/targets → tìm "monitoring/metrics-app"
```

### Step 7: Tạo Alert Rules

```bash
kubectl apply -f manifests/prometheusrule-alerts.yaml
kubectl apply -f manifests/alertmanager-config.yaml

# Kiểm tra rules được load
curl http://localhost:9090/api/v1/rules | python3 -m json.tool | grep -A3 '"name"'

# Xem Alerts đang active
# http://localhost:9090/alerts
```

### Step 8: Tạo Grafana Dashboard

Tạo custom dashboard trong Grafana UI:

1. **Create** → **Dashboard** → **Add visualization**
2. Data source: `Prometheus`
3. Thêm panels:

```
Panel 1: Request Rate
Query: sum(rate(demo_requests_total[5m])) by (endpoint)
Visualization: Time series

Panel 2: Error Rate %  
Query: sum(rate(demo_requests_total{status=~"5.."}[5m])) / sum(rate(demo_requests_total[5m])) * 100
Visualization: Gauge (threshold: 0=green, 5=yellow, 10=red)

Panel 3: P99 Latency
Query: histogram_quantile(0.99, sum(rate(demo_request_duration_seconds_bucket[5m])) by (le, endpoint))
Visualization: Time series

Panel 4: Active Connections
Query: demo_active_connections
Visualization: Stat
```

### Step 9: Import Community Dashboard

```bash
# Truy cập https://grafana.com/grafana/dashboards/
# Dashboard IDs hay dùng:
# 13770 - Kubernetes All-in-one Cluster Monitoring
# 6417  - Kubernetes Cluster (Prometheus)
# 1860  - Node Exporter Full
# 14057 - Kubernetes / Views / Namespaces

# Trong Grafana: Dashboards → Import → Enter Dashboard ID → Load
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# 1. Kiểm tra tất cả Prometheus targets UP
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep '"health"' | sort | uniq -c

# 2. Query custom metrics
curl -s "http://localhost:9090/api/v1/query?query=demo_requests_total" | python3 -m json.tool

# 3. Kiểm tra alerts đang được định nghĩa
curl -s "http://localhost:9090/api/v1/rules?type=alert" | python3 -m json.tool | grep '"name"'

# 4. Kiểm tra Alertmanager running
kubectl port-forward svc/kube-prometheus-stack-alertmanager 9093:9093 -n monitoring &
curl -s http://localhost:9093/api/v2/status | python3 -m json.tool | grep '"status"'

# 5. ServiceMonitor discovered
curl -s "http://localhost:9090/api/v1/targets" | python3 -m json.tool | grep "metrics-app"

# 6. Verify recording rules work
curl -s "http://localhost:9090/api/v1/query?query=job:demo_requests:rate5m" | python3 -m json.tool
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Dừng port-forwards
kill %1 %2 %3 2>/dev/null || true

# Xóa custom resources
kubectl delete -f manifests/servicemonitor-app.yaml
kubectl delete -f manifests/prometheusrule-alerts.yaml
kubectl delete -f manifests/alertmanager-config.yaml
kubectl delete -f manifests/deployment-metrics-app.yaml

# Xóa Helm release (xóa Prometheus, Grafana, Alertmanager)
helm uninstall kube-prometheus-stack -n monitoring

# Xóa CRDs (cẩn thận trong production!)
kubectl get crds | grep monitoring.coreos.com | awk '{print $1}' | xargs kubectl delete crd

# Xóa namespace
kubectl delete namespace monitoring

# Verify
kubectl get pods -n monitoring 2>&1
```

---

## 💡 Tips & Gotchas

### ⚠️ ServiceMonitor không được scrape
```bash
# Kiểm tra labels match
# ServiceMonitor selector phải match Service labels
kubectl get svc metrics-app -n monitoring --show-labels
# Phải có label: app=metrics-app (hoặc match với selector trong ServiceMonitor)

# Kiểm tra Prometheus configuration
curl -s http://localhost:9090/api/v1/status/config | python3 -m json.tool | grep "metrics-app"
```

### ⚠️ PromQL cardinality explosion
```
# TRÁNH:
http_requests_total{user_id="12345"}  # user_id có cardinality cao → OOM

# ĐÚNG: Chỉ dùng labels có cardinality thấp
http_requests_total{endpoint="/api/users", method="GET", status="200"}
```

### ⚠️ Histogram vs Summary
```
Histogram:
  ✅ Có thể aggregate across instances (sum + by)
  ✅ Buckets defined at instrumentation time
  ❌ Less accurate for quantile calculation

Summary:
  ✅ More accurate quantiles
  ❌ Cannot aggregate across instances
  ❌ Quantiles defined at instrumentation time (cannot change without redeploy)
```

### 💡 Recording Rules để tối ưu performance
```yaml
# Trong PrometheusRule, dùng recording rules cho expensive queries
rules:
  - record: job:demo_requests:rate5m
    expr: sum(rate(demo_requests_total[5m])) by (job)
```

### 💡 Grafana variables cho dynamic dashboards
```
# Trong Grafana dashboard settings → Variables:
# Name: namespace
# Query: label_values(kube_pod_info, namespace)
# Sau đó dùng trong query: kube_pod_info{namespace="$namespace"}
```

---

## 📚 Tham khảo (References)

- [Prometheus Documentation](https://prometheus.io/docs/introduction/overview/)
- [PromQL Cheat Sheet](https://promlabs.com/promql-cheat-sheet/)
- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Grafana Dashboard Best Practices](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/best-practices/)
- [Prometheus Operator Docs](https://prometheus-operator.dev/docs/user-guides/getting-started/)
- [OpenMetrics Standard](https://openmetrics.io/)
- [Grafana Community Dashboards](https://grafana.com/grafana/dashboards/)

---

## 🔗 Next Lab

➡️ **[Lab 31 — Distributed Tracing with Jaeger](../lab-31-tracing-jaeger/README.md)**

Tiếp theo: Tracing requests qua nhiều microservices với OpenTelemetry và Jaeger.
