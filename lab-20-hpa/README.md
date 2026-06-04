# Lab 20 — Horizontal Pod Autoscaler (HPA)

## 🎯 Mục tiêu (Objectives)

Sau lab này, bạn sẽ hiểu và làm được:
- Cài đặt và cấu hình **Metrics Server** để HPA hoạt động
- Tạo HPA v2 API dựa trên **CPU** và **Memory**
- Hiểu cơ chế **scale behavior** (stabilization window, scale policies)
- Thực hành **load testing** để xem HPA tự động scale
- Theo dõi HPA hoạt động **real-time**
- Phân biệt HPA v1 và HPA v2 API

---

## 📋 Prerequisites

- Hoàn thành Lab 19 (hoặc có cluster Kubernetes đang chạy)
- `kubectl` đã configured
- Cluster có ít nhất 2 worker nodes (để thấy rõ scaling)
- Hiểu cơ bản về Deployments và Resource Requests/Limits

```bash
# Kiểm tra cluster đang hoạt động
kubectl cluster-info
kubectl get nodes

# Kiểm tra Metrics Server đã cài chưa
kubectl top nodes
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### HPA là gì?

**Horizontal Pod Autoscaler (HPA)** tự động tăng/giảm số lượng Pod replicas dựa trên metrics quan sát được (CPU, Memory, custom metrics).

```
┌─────────────────────────────────────────────────────────────┐
│                    HPA Control Loop                          │
│                                                             │
│  ┌──────────┐    metrics    ┌──────────────┐                │
│  │ Metrics  │◄─────────────│   HPA        │                │
│  │ Server   │              │  Controller  │                │
│  └──────────┘              └──────┬───────┘                │
│                                   │ scale                   │
│                            ┌──────▼───────┐                │
│                            │  Deployment  │                │
│                            │  (replicas)  │                │
│                            └──────────────┘                │
└─────────────────────────────────────────────────────────────┘

Sync period: mặc định 15 giây
```

### HPA Algorithm

```
desiredReplicas = ceil[currentReplicas × (currentMetricValue / desiredMetricValue)]

Ví dụ:
- currentReplicas = 3
- currentCPU = 80%
- desiredCPU = 50%
- desiredReplicas = ceil[3 × (80/50)] = ceil[4.8] = 5
```

### HPA v1 vs HPA v2 API

| Feature | HPA v1 | HPA v2 (autoscaling/v2) |
|---------|--------|--------------------------|
| CPU metrics | ✅ | ✅ |
| Memory metrics | ❌ | ✅ |
| Custom metrics | ❌ | ✅ |
| External metrics | ❌ | ✅ |
| Scale behavior | ❌ | ✅ |
| Multiple metrics | ❌ | ✅ |

### Scale Behavior

```yaml
behavior:
  scaleUp:
    stabilizationWindowSeconds: 0    # Scale up ngay lập tức
    policies:
    - type: Percent
      value: 100                     # Tăng tối đa 100% mỗi lần
      periodSeconds: 15
  scaleDown:
    stabilizationWindowSeconds: 300  # Chờ 5 phút trước khi scale down
    policies:
    - type: Pods
      value: 1                       # Giảm tối đa 1 pod mỗi lần
      periodSeconds: 60
```

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Cài đặt Metrics Server

Metrics Server là thành phần bắt buộc để HPA lấy metrics từ các Pod.

```bash
# Cài Metrics Server (cho production cluster)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Nếu dùng Minikube
minikube addons enable metrics-server

# Nếu dùng kind hoặc cluster tự cài (thường cần --kubelet-insecure-tls)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Nếu gặp lỗi TLS với kind/local cluster, patch thêm flag:
kubectl patch deployment metrics-server \
  -n kube-system \
  --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
```

**Chờ Metrics Server sẵn sàng:**
```bash
kubectl -n kube-system rollout status deployment/metrics-server

# Kiểm tra metrics đã có
kubectl top nodes
kubectl top pods -A
```

**Expected output:**
```
NAME        CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
minikube    210m         5%     1024Mi          26%
```

---

### Step 2: Deploy ứng dụng PHP-Apache (demo kinh điển)

Đây là ứng dụng demo chính thức từ Kubernetes docs.

```bash
# Deploy ứng dụng
kubectl apply -f manifests/deployment-php-apache.yaml

# Kiểm tra deployment
kubectl get deployment php-apache
kubectl get pods -l app=php-apache

# Kiểm tra service
kubectl get svc php-apache
```

**Expected output:**
```
NAME         READY   UP-TO-DATE   AVAILABLE   AGE
php-apache   1/1     1            1           30s
```

---

### Step 3: Tạo HPA dựa trên CPU

```bash
# Tạo HPA từ manifest
kubectl apply -f manifests/hpa-cpu.yaml

# Hoặc tạo nhanh bằng kubectl imperative
kubectl autoscale deployment php-apache \
  --cpu-percent=50 \
  --min=1 \
  --max=10 \
  --name=php-apache-cpu-hpa

# Xem trạng thái HPA (ban đầu sẽ thấy TARGETS: <unknown>/50%)
kubectl get hpa
kubectl describe hpa php-apache-hpa
```

**Expected output (khi chưa có load):**
```
NAME              REFERENCE              TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
php-apache-hpa    Deployment/php-apache  1%/50%    1         10        1          30s
```

> ⚠️ Nếu thấy `<unknown>` ở TARGETS, chờ thêm 30-60 giây để Metrics Server sync.

---

### Step 4: Load Testing — Tạo traffic để trigger HPA

```bash
# Mở terminal thứ 2 — chạy load generator
kubectl apply -f manifests/pod-load-generator.yaml

# Theo dõi HPA real-time trong terminal thứ 1
watch -n 5 kubectl get hpa

# Hoặc xem chi tiết hơn
watch -n 5 'kubectl get hpa php-apache-hpa && echo "---" && kubectl get pods -l app=php-apache'
```

**Xem HPA events:**
```bash
kubectl describe hpa php-apache-hpa | grep -A 20 "Events:"
```

**Expected output sau 1-2 phút:**
```
NAME              REFERENCE              TARGETS    MINPODS   MAXPODS   REPLICAS   AGE
php-apache-hpa    Deployment/php-apache  156%/50%   1         10        4          5m

# Pods tăng lên
NAME                          READY   STATUS    RESTARTS   AGE
php-apache-6d5656d5d-2xkq9    1/1     Running   0          5m
php-apache-6d5656d5d-7bk2p    1/1     Running   0          2m ← scaled up
php-apache-6d5656d5d-9hj3r    1/1     Running   0          2m ← scaled up
php-apache-6d5656d5d-xp4m1    1/1     Running   0          2m ← scaled up
```

---

### Step 5: Dừng load và xem Scale Down

```bash
# Xóa load generator
kubectl delete pod load-generator

# Theo dõi HPA scale down (sẽ mất ~5 phút do stabilizationWindowSeconds: 300)
watch -n 10 kubectl get hpa php-apache-hpa
```

> 💡 **Tip**: Scale down chậm hơn scale up là behavior mặc định và intentional — tránh "flapping" (scale lên xuống liên tục).

---

### Step 6: HPA dựa trên Memory

```bash
# Deploy HPA memory-based
kubectl apply -f manifests/hpa-memory.yaml

# Xem chi tiết
kubectl describe hpa php-apache-memory-hpa
```

> ⚠️ **Lưu ý quan trọng**: Memory-based HPA ít phổ biến hơn CPU-based vì:
> - Memory không tự giảm khi Pod không dùng nữa (garbage collection chậm)
> - Scale down dựa trên memory khó hơn → thường gây flapping
> - Thích hợp hơn khi kết hợp với VPA (xem Lab 21)

---

### Step 7: Xem HPA với nhiều metrics

HPA v2 có thể dùng nhiều metrics cùng lúc — HPA sẽ chọn số replicas lớn nhất từ tất cả metrics.

```bash
# Xem manifest hpa-cpu.yaml có phần multiple metrics
kubectl get hpa php-apache-hpa -o yaml

# Kiểm tra metrics hiện tại
kubectl get hpa php-apache-hpa -o jsonpath='{.status.currentMetrics}' | python3 -m json.tool
```

---

### Step 8: Tùy chỉnh Scale Behavior

```bash
# Edit HPA để thêm custom behavior
kubectl edit hpa php-apache-hpa

# Hoặc apply manifest đã có behavior config
kubectl apply -f manifests/hpa-cpu.yaml  # đã có behavior section
```

**Giải thích behavior trong manifest:**
```yaml
behavior:
  scaleUp:
    stabilizationWindowSeconds: 0     # Không chờ khi scale up
    policies:
    - type: Percent
      value: 100                      # Tối đa tăng gấp đôi mỗi 15s
      periodSeconds: 15
    - type: Pods
      value: 4                        # Hoặc tăng tối đa 4 pods mỗi 15s
      periodSeconds: 15
    selectPolicy: Max                 # Chọn policy cho phép scale nhiều hơn
  scaleDown:
    stabilizationWindowSeconds: 300   # Chờ 5 phút trước khi giảm
    policies:
    - type: Pods
      value: 1                        # Giảm 1 pod mỗi phút
      periodSeconds: 60
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# 1. Kiểm tra tất cả HPAs
kubectl get hpa

# 2. Xem chi tiết HPA
kubectl describe hpa php-apache-hpa

# 3. Kiểm tra events liên quan đến scaling
kubectl get events --sort-by='.lastTimestamp' | grep -i "hpa\|scal"

# 4. Xem metrics history (nếu dùng Prometheus)
# kubectl get --raw /apis/metrics.k8s.io/v1beta1/pods | python3 -m json.tool

# 5. Kiểm tra HPA status
kubectl get hpa php-apache-hpa -o jsonpath='{.status}' | python3 -m json.tool

# Expected: conditions với AbleToScale=True, ScalingActive=True
```

**Checklist:**
- [ ] Metrics Server đang chạy và `kubectl top pods` hoạt động
- [ ] HPA hiển thị TARGETS với giá trị thực (không phải `<unknown>`)
- [ ] Sau khi load test, số Pods tăng lên
- [ ] Sau khi dừng load, số Pods giảm về minReplicas (sau ~5 phút)

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xóa load generator nếu còn
kubectl delete pod load-generator --ignore-not-found

# Xóa HPAs
kubectl delete hpa php-apache-hpa --ignore-not-found
kubectl delete hpa php-apache-memory-hpa --ignore-not-found

# Xóa deployment và service
kubectl delete -f manifests/deployment-php-apache.yaml --ignore-not-found

# Xóa tất cả resources của lab
kubectl delete -f manifests/ --ignore-not-found

# Kiểm tra đã sạch chưa
kubectl get hpa
kubectl get pods -l app=php-apache
```

---

## 💡 Tips & Gotchas

### ⚠️ Thường gặp

1. **HPA hiển thị `<unknown>` mãi không ra metrics**
   ```bash
   # Kiểm tra Metrics Server
   kubectl -n kube-system get pods | grep metrics-server
   kubectl -n kube-system logs -l k8s-app=metrics-server | tail -20
   # Thường do TLS issue với local clusters → cần --kubelet-insecure-tls
   ```

2. **HPA không scale dù CPU cao**
   ```bash
   # Kiểm tra resource requests đã set chưa (BẮT BUỘC phải có requests)
   kubectl describe pod <pod-name> | grep -A 5 "Requests:"
   # HPA tính CPU% dựa trên requests, không phải limits!
   ```

3. **Scale down quá chậm**
   ```bash
   # Giảm stabilizationWindowSeconds trong behavior section
   # Default là 300s (5 phút) cho scale down
   ```

4. **Pod Disruption Budget (PDB) cản trở scale down**
   ```bash
   # Kiểm tra PDB
   kubectl get pdb
   # Xem Lab 23 để hiểu PDB
   ```

### 💡 Best Practices

- **Luôn set `resources.requests`** cho containers — HPA không hoạt động nếu thiếu
- Dùng **CPU-based HPA** cho stateless services
- Dùng **custom metrics** (request/second, queue depth) cho microservices
- Set **minReplicas ≥ 2** cho HA (không để về 0 trừ khi dùng KEDA)
- **Scale down stabilization window** ≥ 3 phút để tránh flapping
- Kết hợp HPA với **PodDisruptionBudget** (xem Lab 23)

---

## 📚 Tham khảo (References)

- [Kubernetes HPA Documentation](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [HPA Walkthrough](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/)
- [HPA Algorithm Details](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#algorithm-details)
- [Metrics Server GitHub](https://github.com/kubernetes-sigs/metrics-server)
- [KEDA - Kubernetes Event-driven Autoscaling](https://keda.sh/) (advanced)

---

## 🔗 Next Lab

➡️ **[Lab 21 — Vertical Pod Autoscaler (VPA)](../lab-21-vpa/README.md)**

HPA scale số lượng Pods theo chiều ngang. Lab 21 sẽ học VPA — tự động điều chỉnh CPU/Memory **requests** của từng Pod theo chiều dọc.
