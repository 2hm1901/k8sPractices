# Lab 32 — Health Checks: Liveness, Readiness & Startup Probes

## 🎯 Mục tiêu

Sau lab này bạn sẽ:
- Phân biệt rõ 3 loại probe: **Liveness**, **Readiness**, **Startup**
- Cấu hình probe types: **httpGet**, **tcpSocket**, **exec**, **grpc**
- Tuning các tham số probe: `initialDelaySeconds`, `periodSeconds`, `failureThreshold`
- Implement `preStop` hook để graceful shutdown
- Tránh các anti-pattern phổ biến khi cấu hình probe

## 📋 Prerequisites

- Hoàn thành Lab 06 (Deployment)
- Hoàn thành Lab 10 (Service)

## 🧠 Lý thuyết nhanh

```
┌─────────────────────────────────────────────────────────────────┐
│                    Pod Health Checks                             │
│                                                                 │
│  STARTUP PROBE                                                  │
│  └── Dành cho slow-start app. Disable liveness trong startup.  │
│      Fail → container restart                                   │
│                                                                 │
│  LIVENESS PROBE                                                 │
│  └── App còn sống không? Deadlock?                             │
│      Fail → container restart (kubelet kills it)               │
│                                                                 │
│  READINESS PROBE                                                │
│  └── App sẵn sàng nhận traffic chưa?                          │
│      Fail → remove Pod from Service endpoints (no traffic)     │
│      ≠ container restart!                                       │
└─────────────────────────────────────────────────────────────────┘
```

### So sánh 3 loại Probe

| | Liveness | Readiness | Startup |
|--|---------|-----------|---------|
| **Fail action** | Restart container | Stop traffic | Restart container |
| **Khi nào dùng** | Phát hiện deadlock | Warmup/loading | App khởi động chậm |
| **Ảnh hưởng rolling update** | Không | Có | Có |

## 🛠️ Thực hành

### Step 1: Liveness Probe — HTTP

```bash
kubectl apply -f manifests/pod-liveness-http.yaml
kubectl get pod liveness-http-demo -w

# Xem probe hoạt động
kubectl describe pod liveness-http-demo | grep -A 10 "Liveness"
```

Mô phỏng app unhealthy:
```bash
# Exec vào pod và tạo file /unhealthy để trigger liveness fail
kubectl exec liveness-http-demo -- touch /unhealthy

# Xem pod restart
kubectl get pod liveness-http-demo -w
# → RESTARTS tăng lên 1
```

### Step 2: Readiness Probe — Không restart, chỉ remove khỏi Service

```bash
kubectl apply -f manifests/pod-readiness-http.yaml

# Xem pod status
kubectl get pod readiness-demo
# READY: 0/1 → 1/1 sau khi warmup xong

# Kiểm tra endpoints
kubectl get endpoints  # Pod chỉ xuất hiện khi READY=1/1
```

### Step 3: Startup Probe — Cho slow-start app

```bash
kubectl apply -f manifests/pod-startup-probe.yaml
kubectl get pod slow-start-app -w

# Startup probe cho phép app mất đến 5min để khởi động:
# failureThreshold (30) × periodSeconds (10) = 300 giây = 5 phút
kubectl describe pod slow-start-app | grep -A 5 "Startup"
```

### Step 4: Exec Probe — Command-based

```bash
kubectl apply -f manifests/pod-exec-probe.yaml
kubectl describe pod exec-probe-demo | grep -A 5 "Liveness"
```

### Step 5: TCP Socket Probe

```bash
kubectl apply -f manifests/pod-tcp-probe.yaml
kubectl describe pod tcp-probe-demo | grep -A 5 "Readiness"
```

### Step 6: Deployment với tất cả 3 probe

```bash
kubectl apply -f manifests/deployment-full-probes.yaml
kubectl rollout status deployment/full-probes-app

# Xem probe config
kubectl describe deployment full-probes-app | grep -A 30 "Containers"
```

### Step 7: preStop Hook — Graceful Shutdown

```bash
kubectl apply -f manifests/pod-prestop-hook.yaml

# Xóa pod và quan sát graceful shutdown
kubectl delete pod prestop-demo
# Pod không bị kill ngay, chạy preStop hook trước (sleep 10)
kubectl get pod prestop-demo -w
```

## ✅ Kiểm tra kết quả

```bash
# Xem probe status từng pod
kubectl describe pod liveness-http-demo | grep -E "(Liveness|Readiness|Startup|Ready)"

# Xem restart count (chứng minh liveness hoạt động)
kubectl get pod --sort-by='.status.containerStatuses[0].restartCount'

# Endpoint chỉ có pod READY
kubectl get endpoints
```

## 🧹 Dọn dẹp

```bash
kubectl delete -f manifests/
```

## 💡 Tips & Gotchas

- **Anti-pattern**: Liveness probe gọi external dependency (DB) → nếu DB down, tất cả pod restart cascade!
- **Best practice**: Liveness probe chỉ check internal health (không phụ thuộc external)
- **Anti-pattern**: `initialDelaySeconds` quá nhỏ → pod restart liên tục vì probe fail trước khi app ready
- **Tip**: Dùng Startup Probe thay vì tăng `initialDelaySeconds` lên cao
- **Gotcha**: Readiness probe fail không restart container — pod vẫn chạy, chỉ bị remove khỏi Service
- **Tip**: `terminationGracePeriodSeconds` phải > thời gian preStop hook để graceful shutdown đúng cách

## 📚 Tham khảo

- [Configure Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)

## 🔗 Next Lab

➡️ [Lab 33 — Helm Package Manager](../lab-33-helm/README.md)
