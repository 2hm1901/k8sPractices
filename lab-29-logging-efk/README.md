# Lab 29 — Logging với EFK Stack (Elasticsearch + Fluentd + Kibana)

## 🎯 Mục tiêu (Objectives)

Sau lab này, bạn sẽ hiểu và thực hành được:
- Kiến trúc logging trong Kubernetes (stdout/stderr → node logs → log aggregator)
- Sự khác biệt giữa EFK và ELK stack
- Triển khai Fluentd dưới dạng DaemonSet để thu thập log từ tất cả các node
- Cấu hình Elasticsearch để lưu trữ và đánh chỉ mục log
- Sử dụng Kibana để visualize và search log
- Áp dụng structured JSON logging best practices
- Xử lý multi-line logs (stack traces)
- Thiết lập log retention policy

---

## 📋 Prerequisites

- Hoàn thành Lab 28 (hoặc có cluster Kubernetes đang chạy)
- `kubectl` configured và kết nối được với cluster
- Cluster có ít nhất **4GB RAM** khả dụng (Elasticsearch cần nhiều bộ nhớ)
- Helm 3 đã cài đặt (optional nhưng recommended)
- Docker cài đặt nếu muốn build custom images

```bash
# Kiểm tra cluster resources
kubectl top nodes

# Kiểm tra Helm
helm version
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Kiến trúc Kubernetes Logging

Kubernetes không có built-in centralized logging. Log flow theo 3 tầng:

```
┌─────────────────────────────────────────────────────┐
│                   Kubernetes Node                    │
│  ┌──────────────┐    ┌──────────────┐               │
│  │    Pod A     │    │    Pod B     │               │
│  │  Container   │    │  Container   │               │
│  │  stdout/err  │    │  stdout/err  │               │
│  └──────┬───────┘    └──────┬───────┘               │
│         │                   │                        │
│         ▼                   ▼                        │
│  /var/log/containers/*.log (symlinks)                │
│  /var/log/pods/<pod>/<container>/*.log               │
│         │                                            │
│  ┌──────▼──────────────────────┐                    │
│  │   Fluentd DaemonSet Pod     │  ← runs on each node│
│  │   (log collector/forwarder) │                    │
│  └──────────────┬──────────────┘                    │
└─────────────────┼────────────────────────────────────┘
                  │
          ┌───────▼────────┐
          │ Elasticsearch  │  ← stores & indexes
          │   (StatefulSet)│
          └───────┬────────┘
                  │
          ┌───────▼────────┐
          │    Kibana      │  ← visualize & search
          └────────────────┘
```

### EFK vs ELK

| Component | EFK Stack | ELK Stack |
|-----------|-----------|-----------|
| E | Elasticsearch | Elasticsearch |
| F/L | **Fluentd** (cloud-native, K8s-friendly) | **Logstash** (heavier, JVM-based) |
| K | Kibana | Kibana |

**Tại sao chọn Fluentd cho K8s?**
- Là CNCF project, được thiết kế cho cloud-native
- Nhẹ hơn Logstash (Ruby-based với C extensions)
- Native support cho Kubernetes metadata enrichment
- Plugin ecosystem phong phú
- Fluentbit (Go-based) còn nhẹ hơn, dùng làm forwarder

### Log Rotation trong K8s

```
Container Runtime (containerd/docker)
  → /var/log/containers/<name>-<id>.log
  → Rotated by kubelet (--container-log-max-size=10Mi, --container-log-max-files=5)
  
Node-level logs:
  → journald (systemd) hoặc /var/log/*.log
  → Managed by logrotate
```

### Structured JSON Logging Best Practices

```json
{
  "timestamp": "2026-06-04T07:51:37Z",
  "level": "INFO",
  "service": "payment-service",
  "trace_id": "abc-123-def",
  "span_id": "xyz-789",
  "message": "Payment processed successfully",
  "amount": 99.99,
  "currency": "USD",
  "user_id": "usr_456",
  "duration_ms": 42
}
```

**Lợi ích**: Dễ parse, filter, aggregate, và alert trong Elasticsearch.

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Tạo Namespace và RBAC

```bash
kubectl apply -f manifests/namespace-logging.yaml
kubectl apply -f manifests/fluentd-serviceaccount-rbac.yaml
```

Kiểm tra:
```bash
kubectl get namespace logging
kubectl get serviceaccount -n logging
kubectl get clusterrole fluentd
```

### Step 2: Triển khai Elasticsearch

Elasticsearch cần persistent storage và khá tốn RAM. Trong lab này ta dùng `emptyDir` để đơn giản.

```bash
kubectl apply -f manifests/elasticsearch-deployment.yaml
kubectl apply -f manifests/elasticsearch-service.yaml
```

Chờ Elasticsearch ready:
```bash
kubectl rollout status deployment/elasticsearch -n logging
kubectl logs deployment/elasticsearch -n logging | tail -20
```

Test Elasticsearch:
```bash
# Port-forward để test local
kubectl port-forward svc/elasticsearch 9200:9200 -n logging &

# Test health
curl -s http://localhost:9200/_cluster/health | python3 -m json.tool
# Expected: "status": "green" hoặc "yellow"

curl -s http://localhost:9200/_cat/indices?v
```

### Step 3: Cấu hình và Deploy Fluentd

Fluentd ConfigMap định nghĩa cách thu thập và parse logs:

```bash
kubectl apply -f manifests/fluentd-configmap.yaml
kubectl apply -f manifests/fluentd-daemonset.yaml
```

Kiểm tra Fluentd chạy trên mọi node:
```bash
kubectl get daemonset -n logging
# DESIRED = số node trong cluster
# READY phải bằng DESIRED

kubectl get pods -n logging -l app=fluentd -o wide
# Mỗi node phải có 1 pod Fluentd
```

Xem logs của Fluentd để debug:
```bash
kubectl logs -n logging -l app=fluentd --tail=50
```

### Step 4: Triển khai Kibana

```bash
kubectl apply -f manifests/kibana-deployment.yaml
kubectl apply -f manifests/kibana-service.yaml

kubectl rollout status deployment/kibana -n logging
```

Truy cập Kibana:
```bash
kubectl port-forward svc/kibana 5601:5601 -n logging
# Mở browser: http://localhost:5601
```

### Step 5: Deploy Demo App với Structured Logging

```bash
kubectl apply -f manifests/pod-structured-logging.yaml
```

Xem logs của demo app:
```bash
kubectl logs -n logging -l app=demo-logger --follow
```

### Step 6: Cấu hình Kibana Index Pattern

Sau khi có logs, cấu hình Kibana:

1. Vào **Stack Management** → **Index Patterns**
2. Tạo index pattern: `logstash-*` (Fluentd dùng prefix này)
3. Chọn **@timestamp** làm time field
4. Nhấn **Create index pattern**

### Step 7: Khám phá Logs trong Kibana

Truy cập **Discover** trong Kibana:

```
Useful KQL (Kibana Query Language) queries:

# Filter by namespace
kubernetes.namespace_name: "default"

# Filter by app label
kubernetes.labels.app: "demo-logger"

# Find error logs
level: "ERROR"

# Search by trace_id
trace_id: "abc-123-def"

# Combine queries
kubernetes.namespace_name: "default" AND level: "ERROR"

# Time-based search (dùng time picker ở góc trên phải)
```

### Step 8: Cấu hình Log Retention (Index Lifecycle Management)

```bash
# Tạo ILM policy để tự động xóa log cũ
curl -X PUT "http://localhost:9200/_ilm/policy/logs-policy" \
  -H 'Content-Type: application/json' \
  -d '{
    "policy": {
      "phases": {
        "hot": {
          "actions": {
            "rollover": {
              "max_size": "10gb",
              "max_age": "1d"
            }
          }
        },
        "delete": {
          "min_age": "7d",
          "actions": {
            "delete": {}
          }
        }
      }
    }
  }'
```

### Step 9: Xử lý Multi-line Logs (Stack Traces)

Multi-line logs (Java stack traces) là thách thức vì mỗi dòng được ghi thành 1 log event:

```
# Java Exception
java.lang.NullPointerException
    at com.example.App.main(App.java:10)
    at sun.reflect.NativeMethodAccessorImpl.invoke0(Native Method)
```

Fluentd ConfigMap đã bao gồm `multiline` parser để ghép lại:

```
<filter **>
  @type concat
  key message
  multiline_start_regexp /^\d{4}-\d{2}-\d{2}/
  flush_interval 5s
</filter>
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# 1. Kiểm tra tất cả pods trong namespace logging
kubectl get pods -n logging -o wide

# 2. Kiểm tra DaemonSet coverage
kubectl get ds fluentd -n logging
# DESIRED = CURRENT = READY = số node

# 3. Kiểm tra Fluentd không có lỗi
kubectl logs -n logging -l app=fluentd | grep -i error

# 4. Verify Elasticsearch nhận được logs
curl -s "http://localhost:9200/_cat/indices?v&index=logstash-*"
# Phải thấy indices với docs.count > 0

# 5. Test search API trực tiếp
curl -s "http://localhost:9200/logstash-*/_search?q=level:INFO&size=1" | python3 -m json.tool

# 6. Verify Kibana accessible
curl -s http://localhost:5601/api/status | python3 -m json.tool | grep -A2 '"overall"'
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Dừng port-forwards
kill %1 %2 2>/dev/null || true

# Xóa toàn bộ namespace logging (xóa tất cả resources bên trong)
kubectl delete namespace logging

# Xóa ClusterRole và ClusterRoleBinding (cluster-scoped, không bị xóa cùng namespace)
kubectl delete clusterrole fluentd
kubectl delete clusterrolebinding fluentd

# Verify đã xóa sạch
kubectl get all -n logging 2>&1 | head -5
```

---

## 💡 Tips & Gotchas

### ⚠️ Elasticsearch cần nhiều RAM
```bash
# Elasticsearch mặc định cần 1GB heap
# Trong production, cần ít nhất 4GB total RAM cho ES
# Trong lab, ta limit xuống 512MB với JVM opts:
# ES_JAVA_OPTS: "-Xms512m -Xmx512m"

# Nếu ES OOMKilled:
kubectl describe pod -n logging -l app=elasticsearch | grep -A5 "OOMKilled"
```

### ⚠️ vm.max_map_count trên host
```bash
# Elasticsearch yêu cầu vm.max_map_count >= 262144
# Nếu dùng kind/minikube:
docker exec -it <node-container> sysctl -w vm.max_map_count=262144

# Minikube:
minikube ssh "sudo sysctl -w vm.max_map_count=262144"
```

### ⚠️ Fluentd permission errors
```bash
# Nếu Fluentd không đọc được /var/log, kiểm tra RBAC
kubectl auth can-i get pods --as=system:serviceaccount:logging:fluentd -n logging
```

### 💡 Fluentbit thay thế Fluentd
```
Fluentbit (nhẹ hơn) thường được dùng làm daemonset trên nodes
Fluentd dùng làm aggregator (ít replicas hơn)
Architecture: Fluentbit → Fluentd → Elasticsearch
```

### 💡 Log Levels và Sampling
```
Trong production, tránh log ở level DEBUG liên tục.
Dùng dynamic log level adjustment hoặc log sampling cho high-volume services.
```

---

## 📚 Tham khảo (References)

- [Kubernetes Logging Architecture](https://kubernetes.io/docs/concepts/cluster-administration/logging/)
- [Fluentd Documentation](https://docs.fluentd.org/)
- [Elasticsearch Guide](https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html)
- [Kibana Guide](https://www.elastic.co/guide/en/kibana/current/index.html)
- [Fluent Bit for Kubernetes](https://docs.fluentbit.io/manual/installation/kubernetes)
- [OpenTelemetry Logging](https://opentelemetry.io/docs/specs/otel/logs/)

---

## 🔗 Next Lab

➡️ **[Lab 30 — Metrics with Prometheus & Grafana](../lab-30-prometheus-grafana/README.md)**

Tiếp theo: Thu thập metrics với Prometheus và visualize với Grafana dashboard.
