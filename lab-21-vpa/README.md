# Lab 21 — Vertical Pod Autoscaler (VPA)

## 🎯 Mục tiêu (Objectives)

Sau lab này, bạn sẽ hiểu và làm được:
- Hiểu kiến trúc VPA: **Recommender**, **Updater**, **Admission Controller**
- Cài đặt VPA vào cluster
- Thực hành 3 chế độ VPA: **Off**, **Initial**, **Auto**
- Biết khi nào dùng **VPA vs HPA**
- Xem VPA recommendations để tối ưu resource requests
- Hiểu VPA limitations và cách làm việc với multi-container pods

---

## 📋 Prerequisites

- Hoàn thành Lab 20 (HPA đã hiểu)
- Metrics Server đã được cài đặt (từ Lab 20)
- `kubectl` đã configured
- Cluster có quyền deploy CRDs (VPA dùng CRDs)

```bash
# Kiểm tra Metrics Server
kubectl top nodes

# Kiểm tra VPA chưa được cài
kubectl get crd | grep verticalpodautoscaler
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### VPA là gì?

**Vertical Pod Autoscaler (VPA)** tự động điều chỉnh **CPU và Memory requests/limits** của Pod dựa trên usage thực tế. Thay vì tăng số Pod (horizontal), VPA làm cho mỗi Pod "to hơn" hoặc "nhỏ hơn" (vertical).

```
┌─────────────────────────────────────────────────────────┐
│                   VPA Components                         │
│                                                         │
│  ┌─────────────┐  ┌─────────────┐  ┌────────────────┐  │
│  │ Recommender │  │   Updater   │  │   Admission    │  │
│  │             │  │             │  │   Controller   │  │
│  │ Analyze     │  │ Evict pods  │  │ Set resources  │  │
│  │ metrics →   │  │ that need   │  │ on new pods    │  │
│  │ recommend   │  │ updating    │  │ at creation    │  │
│  │ resources   │  │             │  │                │  │
│  └──────┬──────┘  └─────────────┘  └────────────────┘  │
│         │                                               │
│         ▼ VPA Object (recommendations)                  │
│  ┌─────────────────────────────┐                        │
│  │  lowerBound: cpu=50m        │                        │
│  │  target:     cpu=200m  ←────┼── dùng cái này         │
│  │  upperBound: cpu=800m       │                        │
│  │  uncappedTarget: cpu=1200m  │                        │
│  └─────────────────────────────┘                        │
└─────────────────────────────────────────────────────────┘
```

### VPA Modes

| Mode | Recommender | Updater | Admission Controller | Dùng khi |
|------|-------------|---------|----------------------|----------|
| **Off** | ✅ Chạy | ❌ Không | ❌ Không | Chỉ muốn xem recommendations |
| **Initial** | ✅ Chạy | ❌ Không | ✅ Chạy | Set resources khi pod mới tạo |
| **Auto** | ✅ Chạy | ✅ Chạy | ✅ Chạy | Tự động update (evict + recreate) |
| **Recreate** | ✅ Chạy | ✅ Chạy | ✅ Chạy | Giống Auto nhưng rõ ràng hơn |

### VPA vs HPA — Khi nào dùng cái nào?

```
┌──────────────────────────────────────────────────────────────┐
│         VPA                    vs          HPA               │
│                                                              │
│  ✅ Stateful applications         ✅ Stateless services       │
│  ✅ Single-instance services      ✅ Web APIs / front-end      │
│  ✅ Ứng dụng không scale ngang    ✅ High-traffic workloads    │
│  ✅ Optimize resource usage       ✅ Handle traffic spikes     │
│  ✅ JVM/Node.js (fixed heap)      ✅ CPU-bound tasks           │
│                                                              │
│  ❌ VPA không dùng với HPA         ❌ HPA cần stateless app    │
│     cùng metric (CPU/Mem)                                    │
└──────────────────────────────────────────────────────────────┘

Kết hợp được: VPA (memory) + HPA (custom metrics như request/s)
```

### VPA Limitations

1. **Pod phải restart** để apply recommendations mới (evict + recreate)
2. **Không tương thích với HPA** trên cùng metric (CPU/Memory)
3. **Yêu cầu ít nhất 8+ data points** để có recommendations chính xác
4. **Giới hạn resource có thể** bị capped bởi `LimitRange` của namespace

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Cài đặt VPA

VPA không có sẵn trong Kubernetes — phải cài riêng.

```bash
# Clone VPA repository
git clone https://github.com/kubernetes/autoscaler.git
cd autoscaler/vertical-pod-autoscaler

# Cài VPA (bao gồm CRDs + components)
./hack/vpa-up.sh

# Kiểm tra VPA components đã chạy
kubectl get pods -n kube-system | grep vpa
```

**Expected output:**
```
vpa-admission-controller-7c9d4b7f8-xr2p9   1/1     Running   0   2m
vpa-recommender-6d5f9c8b7-kj4m2             1/1     Running   0   2m
vpa-updater-7b8c9d4f5-np3q1                 1/1     Running   0   2m
```

**Kiểm tra VPA CRDs:**
```bash
kubectl get crd | grep verticalpodautoscaler
# verticalpodautoscalers.autoscaling.k8s.io
# verticalpodautoscalercheckpoints.autoscaling.k8s.io
```

> **Alternative (Helm):**
> ```bash
> helm repo add fairwinds-stable https://charts.fairwinds.com/stable
> helm install vpa fairwinds-stable/vpa --namespace kube-system
> ```

---

### Step 2: Deploy ứng dụng demo

```bash
# Deploy ứng dụng cần tối ưu resources
kubectl apply -f manifests/deployment-for-vpa.yaml

# Kiểm tra pods đang chạy
kubectl get pods -l app=vpa-demo

# Xem resource requests hiện tại (set thủ công, chưa tối ưu)
kubectl describe pod -l app=vpa-demo | grep -A 10 "Requests:"
```

**Expected output (resource requests ban đầu chưa tối ưu):**
```
Requests:
  cpu:        100m
  memory:     64Mi
```

---

### Step 3: VPA Mode "Off" — Chỉ xem Recommendations

Mode `Off` an toàn nhất — VPA chỉ **recommend**, không thay đổi gì.

```bash
# Tạo VPA ở mode Off
kubectl apply -f manifests/vpa-off-mode.yaml

# Xem VPA đã tạo
kubectl get vpa

# Chờ ~5 phút để Recommender có đủ data
# Xem recommendations
kubectl describe vpa vpa-demo-off
```

**Expected output recommendations:**
```yaml
Status:
  Conditions:
    Last Transition Time:  2024-01-15T10:00:00Z
    Status:                True
    Type:                  RecommendationProvided
  Recommendation:
    Container Recommendations:
      Container Name:  demo-app
      Lower Bound:
        Cpu:     25m
        Memory:  32Mi
      Target:
        Cpu:     100m       ← Dùng giá trị này
        Memory:  128Mi      ← Dùng giá trị này
      Uncapped Target:
        Cpu:     100m
        Memory:  128Mi
      Upper Bound:
        Cpu:     800m
        Memory:  512Mi
```

```bash
# Lấy recommendation dưới dạng JSON
kubectl get vpa vpa-demo-off -o jsonpath='{.status.recommendation}' | python3 -m json.tool

# Xem VPA checkpoint (lịch sử data)
kubectl get verticalpodautoscalercheckpoints
```

---

### Step 4: VPA Mode "Initial" — Set resources khi Pod mới tạo

Mode `Initial` chỉ apply recommendations khi **Pod được tạo mới** (không evict pods hiện tại).

```bash
# Tạo VPA ở mode Initial
kubectl apply -f manifests/vpa-initial-mode.yaml

# Xem VPA
kubectl get vpa vpa-demo-initial

# Restart deployment để pods mới được tạo với resources từ VPA
kubectl rollout restart deployment/vpa-demo

# Xem resource requests của pods mới
kubectl describe pod -l app=vpa-demo | grep -A 10 "Requests:"
```

**Expected output (resources được set bởi VPA Admission Controller):**
```
Requests:
  cpu:     100m      ← Set bởi VPA, không phải manifest
  memory:  128Mi     ← Set bởi VPA, không phải manifest
```

---

### Step 5: VPA Mode "Auto" — Tự động update pods đang chạy

Mode `Auto` là mạnh nhất — VPA sẽ **evict và recreate** Pods khi cần điều chỉnh resources.

```bash
# ⚠️ CẢNH BÁO: Mode Auto sẽ restart pods!
# Đảm bảo deployment có đủ replicas (≥ 2) trước khi dùng

# Tạo VPA ở mode Auto
kubectl apply -f manifests/vpa-auto-mode.yaml

# Xem VPA
kubectl get vpa vpa-demo-auto

# Theo dõi pods bị evict và recreate
kubectl get pods -l app=vpa-demo -w

# Xem events
kubectl get events --sort-by='.lastTimestamp' | grep -i "vpa\|evict"
```

**Expected: VPA sẽ evict pods và recreate với resources đã tối ưu**

---

### Step 6: VPA với Multi-container Pods

```bash
# Xem deployment có 2 containers: app + sidecar
kubectl describe pod -l app=vpa-multi | grep -A 20 "Containers:"

# VPA recommendation cho từng container
kubectl describe vpa vpa-multi-container
```

**Phân tích recommendations cho nhiều containers:**
```yaml
Container Recommendations:
  Container Name:  app           # Container chính
    Target:
      Cpu:     200m
      Memory:  256Mi
  Container Name:  log-sidecar  # Sidecar container
    Target:
      Cpu:     25m
      Memory:  32Mi
```

---

### Step 7: Generate load để có recommendations chính xác hơn

```bash
# Tạo load trên VPA demo app
kubectl run load-gen --image=busybox --restart=Never -- \
  sh -c 'while true; do wget -q -O- http://vpa-demo-svc/; done'

# Chờ 10-15 phút để Recommender có đủ data
# Sau đó xem updated recommendations
watch -n 30 'kubectl describe vpa vpa-demo-auto | grep -A 20 "Recommendation:"'

# Xóa load gen sau khi test
kubectl delete pod load-gen
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# 1. Kiểm tra tất cả VPAs
kubectl get vpa

# Expected:
# NAME               MODE   CPU   MEM       PROVIDED   AGE
# vpa-demo-off       Off    100m  128Mi     True       10m
# vpa-demo-initial   Initial 100m 128Mi    True       8m
# vpa-demo-auto      Auto   100m  128Mi     True       5m

# 2. Xem chi tiết từng VPA
kubectl describe vpa vpa-demo-off
kubectl describe vpa vpa-demo-auto

# 3. Kiểm tra resources được apply đúng
kubectl get pods -l app=vpa-demo -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].resources}{"\n"}{end}'

# 4. Kiểm tra VPA components hoạt động
kubectl -n kube-system logs -l app=vpa-recommender --tail=20
kubectl -n kube-system logs -l app=vpa-updater --tail=20
```

**Checklist:**
- [ ] VPA CRDs đã được cài đặt
- [ ] 3 VPA components đang Running
- [ ] `kubectl get vpa` hiển thị PROVIDED=True
- [ ] Mode Off: recommendations hiển thị, pods KHÔNG restart
- [ ] Mode Initial: pods mới có resources từ VPA
- [ ] Mode Auto: pods được evict và recreate với resources tối ưu

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xóa tất cả VPA objects
kubectl delete vpa vpa-demo-off vpa-demo-initial vpa-demo-auto --ignore-not-found

# Xóa deployment
kubectl delete -f manifests/ --ignore-not-found

# Xóa load generator nếu còn
kubectl delete pod load-gen --ignore-not-found

# (Optional) Gỡ cài VPA hoàn toàn
# cd autoscaler/vertical-pod-autoscaler && ./hack/vpa-down.sh

# Kiểm tra đã sạch
kubectl get vpa
kubectl get pods -l app=vpa-demo
```

---

## 💡 Tips & Gotchas

### ⚠️ Thường gặp

1. **VPA không có recommendations sau nhiều phút**
   ```bash
   # Kiểm tra Recommender logs
   kubectl -n kube-system logs -l app=vpa-recommender | grep ERROR
   # Thường do Metrics Server chưa có đủ data (cần ≥ 8 samples)
   # Tăng traffic để có data nhanh hơn
   ```

2. **VPA Mode Auto làm app bị downtime**
   ```bash
   # Giải pháp: Đảm bảo replicas ≥ 2 + PodDisruptionBudget
   # VPA sẽ không evict nếu vi phạm PDB
   kubectl get pdb
   ```

3. **VPA và HPA conflict**
   ```bash
   # KHÔNG dùng VPA Auto + HPA CPU/Memory cùng một workload
   # Được phép: VPA + HPA (dùng custom metrics như request/s)
   ```

4. **Resources sau VPA bị giới hạn bởi LimitRange**
   ```bash
   kubectl describe limitrange
   # VPA recommendations bị capped bởi LimitRange constraints
   ```

### 💡 Best Practices

- **Bắt đầu với mode Off** để xem recommendations trước khi apply
- **Dùng `minAllowed` và `maxAllowed`** để giới hạn VPA recommendations
- VPA phù hợp cho **stateful apps** (databases, ML workloads)
- Kết hợp VPA với **PodDisruptionBudget** để tránh downtime
- Chạy VPA ít nhất **24-48 giờ** trong production để có recommendations chính xác
- Dùng **VPA Off mode** trong staging để gather recommendations, apply thủ công vào production

---

## 📚 Tham khảo (References)

- [VPA GitHub Repository](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
- [VPA Design Proposal](https://github.com/kubernetes/design-proposals-archive/blob/main/autoscaling/vertical-pod-autoscaler.md)
- [VPA vs HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#support-for-resource-metrics)
- [Goldilocks - VPA dashboard](https://github.com/FairwindsOps/goldilocks)

---

## 🔗 Next Lab

➡️ **[Lab 22 — Taints, Tolerations & Node Affinity](../lab-22-scheduling/README.md)**

Sau khi học cách tự động scale Pods, Lab 22 sẽ học cách **kiểm soát Pod được schedule lên node nào** thông qua Taints, Tolerations, và Node/Pod Affinity.
