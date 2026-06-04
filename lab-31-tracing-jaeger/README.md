# Lab 31 — Distributed Tracing với Jaeger & OpenTelemetry

## 🎯 Mục tiêu (Objectives)

Sau lab này, bạn sẽ hiểu và thực hành được:
- Tại sao cần distributed tracing trong microservices (latency debugging)
- OpenTelemetry (OTel) là gì và tại sao nó là standard hiện đại
- Concepts cốt lõi: Trace, Span, Context Propagation
- Kiến trúc Jaeger (Collector, Query, UI)
- W3C TraceContext để propagate trace ID qua HTTP headers
- Auto-instrumentation vs manual instrumentation
- Các chiến lược sampling (head-based, tail-based)
- Tích hợp với Prometheus metrics và logs (Unified Observability)

---

## 📋 Prerequisites

- Hoàn thành Lab 30 (Prometheus & Grafana đang chạy, hiểu observability)
- `kubectl` kết nối được với cluster
- Hiểu cơ bản về HTTP requests và microservices
- Python 3 hoặc Go (để hiểu code examples)

```bash
# Kiểm tra namespace tracing
kubectl get namespace tracing 2>/dev/null || echo "Namespace not found, will create"
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Tại sao cần Distributed Tracing?

Trong kiến trúc microservices, một request của user có thể đi qua nhiều services:

```
User Request
    │
    ▼
[API Gateway] ──(10ms)──► [User Service] ──(5ms)──► [Auth Service]
    │                           │
    │                      (15ms)
    │                           ▼
    │                    [Order Service] ──(200ms)──► [Database]
    │                           │
    │                      (50ms)
    │                           ▼
    │                  [Inventory Service] ──(5ms)──► [Cache]
    │                           │
    │                      (25ms)
    │                           ▼
    │                  [Notification Service] ──(2ms)──► [Email API]
    │
Total: 312ms ← Where is the bottleneck?
```

**Logging**: Biết LỖI ở đâu, nhưng không biết LATENCY ở đâu  
**Metrics**: Biết latency của từng service riêng lẻ, nhưng không thấy FLOW  
**Tracing**: Thấy toàn bộ journey của request, từng hop tốn bao nhiêu ms

### Concepts Cốt Lõi

```
TRACE = Toàn bộ journey của một request (có Trace ID duy nhất)
├── SPAN = Một operation trong trace (có Span ID, start time, duration)
│   ├── Tags/Attributes = Key-value metadata (http.method, db.statement...)
│   ├── Logs/Events = Timestamped events within the span
│   └── Status = OK / ERROR
│
├── ROOT SPAN = Điểm khởi đầu (thường là API Gateway)
│
└── CHILD SPANS = Nested operations (DB calls, external APIs...)
```

```
Trace ID: abc-123-def-456                              Duration: 312ms
│
├─[API Gateway]────────────────────────────────────── 0ms → 312ms
│   ├─[User Service]────────────────────────────────── 10ms → 30ms
│   │   └─[Auth Service]──────────────────────────── 12ms → 17ms
│   │
│   └─[Order Service]────────────────────────────────── 30ms → 295ms
│       ├─[Database Query]──────────────────────────── 35ms → 235ms ← SLOW!
│       │
│       └─[Inventory Service]────────────────────────── 240ms → 295ms
│           └─[Cache Hit]────────────────────────────── 241ms → 246ms
```

### OpenTelemetry Architecture

```
Application Code
    │ (OTel SDK)
    ▼
┌─────────────────────────────────────────────┐
│            OTel Collector                    │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐  │
│  │ Receiver │→ │Processor │→ │ Exporter  │  │
│  │(OTLP,    │  │(batch,   │  │(Jaeger,   │  │
│  │ Zipkin,  │  │filter,   │  │Prometheus,│  │
│  │ Jaeger)  │  │enrich)   │  │OTLP,...)  │  │
│  └──────────┘  └──────────┘  └───────────┘  │
└─────────────────────────────────────────────┘
         │                    │
         ▼                    ▼
    [Jaeger]            [Prometheus]
   (traces)              (metrics)
```

### W3C TraceContext Header

```http
# Khi service A gọi service B, nó attach các headers này:
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
             ^^ version
                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ trace-id (16 bytes hex)
                                                 ^^^^^^^^^^^^^^^^ parent-span-id (8 bytes hex)
                                                                  ^^ flags (01=sampled)

tracestate: vendor1=value1,vendor2=value2
```

### Sampling Strategies

```
HEAD-BASED SAMPLING (quyết định ở đầu):
  - Probabilistic: sample 10% của tất cả requests
  - Rate limiting: sample tối đa N requests/second
  - Ưu: Low overhead, simple
  - Nhược: Có thể miss rare errors

TAIL-BASED SAMPLING (quyết định ở cuối, sau khi trace hoàn thành):
  - Luôn giữ traces có lỗi
  - Luôn giữ traces chậm (>1s)
  - Sample phần còn lại
  - Ưu: Không miss important traces
  - Nhược: Cần buffer toàn bộ trace → tốn memory

ADAPTIVE SAMPLING:
  - Tự điều chỉnh sampling rate dựa trên load
  - Jaeger hỗ trợ remote sampling configuration
```

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Tạo Namespace

```bash
kubectl apply -f manifests/namespace-tracing.yaml
```

### Step 2: Deploy Jaeger All-in-One

Jaeger all-in-one là cách đơn giản nhất để test (không dùng cho production):

```bash
kubectl apply -f manifests/jaeger-all-in-one.yaml
kubectl apply -f manifests/jaeger-service.yaml

# Chờ Jaeger ready
kubectl rollout status deployment/jaeger -n tracing

# Verify
kubectl get pods -n tracing
kubectl get svc -n tracing
```

### Step 3: Deploy OpenTelemetry Collector

```bash
kubectl apply -f manifests/otel-collector-config.yaml

# Kiểm tra collector config
kubectl get configmap otel-collector-config -n tracing -o yaml
```

### Step 4: Deploy Demo Microservices

```bash
# Deploy backend service (downstream)
kubectl apply -f manifests/deployment-backend-service.yaml

# Deploy frontend app (calls backend, has tracing)
kubectl apply -f manifests/deployment-traced-app.yaml

# Chờ tất cả ready
kubectl rollout status deployment/backend-service -n tracing
kubectl rollout status deployment/traced-app -n tracing
```

### Step 5: Generate Traces

```bash
# Port-forward traced-app
kubectl port-forward svc/traced-app 8080:8080 -n tracing &

# Generate some requests (each will create a trace)
for i in $(seq 1 20); do
  curl -s http://localhost:8080/api/users > /dev/null
  curl -s http://localhost:8080/api/orders > /dev/null
  curl -s "http://localhost:8080/api/error" > /dev/null  # Intentional error
  sleep 0.5
done

echo "Generated 60 requests with traces"
```

### Step 6: Truy cập Jaeger UI

```bash
kubectl port-forward svc/jaeger-query 16686:16686 -n tracing &

# Mở browser: http://localhost:16686
```

Trong Jaeger UI:
1. **Service**: chọn `traced-app`
2. **Operation**: chọn `/api/users`
3. **Lookback**: `Last 15 minutes`
4. Nhấn **Find Traces**

Explore:
- Click vào một trace để xem timeline
- Expand spans để xem tags và logs
- Filter traces có lỗi: `error=true`
- Filter traces chậm: `minDuration=100ms`

### Step 7: Xem Trace Details

Khi click vào một trace trong Jaeger UI:

```
Trace: 4bf92f3577b34da6a3ce929d0e0e4736    Duration: 245ms    Spans: 5

traced-app    [HTTP GET /api/orders] ──────────────────────── 0ms → 245ms
  ↓ tags: http.method=GET, http.url=/api/orders, http.status_code=200
  ↓ logs: [0ms] "Starting request handler"
  ↓ logs: [5ms] "Calling backend service"

  backend-service  [HTTP GET /orders] ───────────────── 10ms → 220ms
    ↓ tags: http.method=GET, db.system=postgresql
    
    backend-service  [DB Query: SELECT orders] ─────── 15ms → 210ms  ← 195ms!
      ↓ tags: db.statement="SELECT * FROM orders WHERE user_id=?", db.rows=50
      ↓ logs: [210ms] "Query completed, 50 rows returned"

  traced-app  [Serialize Response] ──────────────────── 220ms → 245ms
    ↓ tags: response.size_bytes=12450
```

### Step 8: Tích hợp Traces với Logs (Exemplars)

Khi log có trace_id, bạn có thể jump từ logs → traces:

```bash
# Xem logs của traced-app
kubectl logs -n tracing -l app=traced-app | head -20
```

Output sẽ có trace_id:
```json
{"timestamp":"2026-06-04T07:51:37Z","level":"INFO","trace_id":"4bf92f3577b34da6a3ce929d0e0e4736","span_id":"00f067aa0ba902b7","message":"Processing request","endpoint":"/api/orders","user_id":"usr_123"}
```

Trong Kibana: search `trace_id: "4bf92f3577b34da6a3ce929d0e0e4736"` → link to Jaeger

### Step 9: Remote Sampling Configuration

```bash
# Kiểm tra sampling strategy
curl -s "http://localhost:16686/api/sampling?service=traced-app" | python3 -m json.tool
```

Thay đổi sampling rate (adaptive):
```bash
kubectl exec -n tracing deployment/jaeger -- /go/bin/jaeger-all-in-one --help | grep sampling
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# 1. Jaeger UI accessible
curl -s http://localhost:16686/api/services | python3 -m json.tool
# Expected: {"data":["traced-app","backend-service"],...}

# 2. Traces are being created
curl -s "http://localhost:16686/api/traces?service=traced-app&limit=5" | \
  python3 -m json.tool | grep '"traceID"' | head -5

# 3. Check collector is receiving spans
kubectl logs -n tracing -l app=otel-collector | grep "spans" | tail -5

# 4. Verify both services appear in Jaeger
curl -s http://localhost:16686/api/services | python3 -m json.tool | grep -E "traced-app|backend-service"

# 5. Check for error traces
curl -s "http://localhost:16686/api/traces?service=traced-app&tags=%7B%22error%22%3A%22true%22%7D&limit=5" | \
  python3 -m json.tool | grep '"traceID"'
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Dừng port-forwards
kill %1 %2 2>/dev/null || true

# Xóa namespace (xóa tất cả resources)
kubectl delete namespace tracing

# Verify
kubectl get all -n tracing 2>&1
```

---

## 💡 Tips & Gotchas

### ⚠️ Jaeger All-in-One vs Production Setup
```
Dev/Lab:
  jaeger-all-in-one: in-memory storage, single pod
  → Data lost on restart, not scalable

Production:
  jaeger-collector (stateless, scale horizontally)
  jaeger-query (stateless)
  Storage backend: Elasticsearch, Cassandra, or Kafka
  → Use Jaeger Operator for K8s management
```

### ⚠️ Sampling rate và performance
```
# Không bao giờ trace 100% requests trong production (quá tốn)
# Recommended: 1-10% head-based + tail-based cho errors/slow

# Jaeger SDK default: probabilistic 0.001 (0.1%)
# Để tăng cho lab:
JAEGER_SAMPLER_TYPE=const
JAEGER_SAMPLER_PARAM=1  # 1 = 100% (chỉ dùng cho dev)
```

### ⚠️ Context Propagation là quan trọng nhất
```python
# SAI: Không pass context → broken trace
result = requests.get("http://backend-service/api")

# ĐÚNG: Pass trace context via headers
with tracer.start_as_current_span("http-call") as span:
    headers = {}
    inject(headers)  # Injects traceparent header
    result = requests.get("http://backend-service/api", headers=headers)
```

### 💡 Auto-instrumentation với OTel
```bash
# Python: Dùng opentelemetry-instrument để không cần sửa code
opentelemetry-instrument \
  --traces_exporter jaeger_thrift \
  --service_name my-service \
  python app.py

# Java: Dùng Java Agent
java -javaagent:opentelemetry-javaagent.jar \
  -Dotel.service.name=my-service \
  -Dotel.exporter.otlp.endpoint=http://otel-collector:4317 \
  -jar myapp.jar
```

### 💡 Trace-Metric correlation với Prometheus Exemplars
```
Grafana hỗ trợ Exemplars: Từ Prometheus graph, click vào data point
→ Link trực tiếp đến Jaeger trace tại thời điểm đó

Cần: Prometheus scrape với exemplar support
     Grafana Jaeger datasource configured
```

---

## 📚 Tham khảo (References)

- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Jaeger Documentation](https://www.jaegertracing.io/docs/)
- [W3C TraceContext Specification](https://www.w3.org/TR/trace-context/)
- [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/)
- [Jaeger Operator for Kubernetes](https://github.com/jaegertracing/jaeger-operator)
- [OTel Python Auto-instrumentation](https://opentelemetry.io/docs/instrumentation/python/automatic/)
- [Distributed Tracing in Practice (book)](https://www.oreilly.com/library/view/distributed-tracing-in/9781492056621/)

---

## 🔗 Next Lab

➡️ **[Lab 32 — Health Checks: Probes](../lab-32-probes/README.md)**

Tiếp theo: Cấu hình Liveness, Readiness, và Startup probes để đảm bảo tính sẵn sàng của ứng dụng.
