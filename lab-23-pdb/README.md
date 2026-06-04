# Lab 23 — Pod Disruption Budget (PDB)

## 🎯 Mục tiêu (Objectives)

Sau lab này, bạn sẽ hiểu và làm được:
- Phân biệt **voluntary** vs **involuntary disruption**
- Tạo PDB với `minAvailable` và `maxUnavailable`
- Thực hành `kubectl drain` với PDB được bảo vệ
- Hiểu PDB interact với Rolling Updates như thế nào
- Cấu hình PDB theo dạng số lượng cụ thể và phần trăm
- Best practices cho PDB trong môi trường production

---

## 📋 Prerequisites

- Hoàn thành Lab 22
- Cluster có ít nhất **2 worker nodes**
- Hiểu về Deployments và ReplicaSets

```bash
# Kiểm tra nodes
kubectl get nodes

# Đảm bảo có ít nhất 2 nodes sẵn sàng
kubectl get nodes | grep " Ready"
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Disruptions là gì?

```
┌─────────────────────────────────────────────────────────────────┐
│                    Types of Disruptions                          │
│                                                                  │
│  INVOLUNTARY (ngoài ý muốn - không kiểm soát được)              │
│  ├─ Node hardware failure                                        │
│  ├─ Cloud provider VM được xóa                                   │
│  ├─ Kernel panic                                                 │
│  └─ OOMKilled (Out of Memory)                                    │
│                                                                  │
│  VOLUNTARY (có chủ đích - PDB có thể bảo vệ)                    │
│  ├─ kubectl drain (node maintenance)                             │
│  ├─ kubectl delete pod                                           │
│  ├─ Deployment rolling update                                    │
│  ├─ kubectl taint ... NoExecute                                  │
│  └─ Cluster autoscaler scale down                                │
│                                                                  │
│  PDB chỉ bảo vệ khỏi VOLUNTARY disruptions!                     │
└─────────────────────────────────────────────────────────────────┘
```

### PDB Anatomy

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-pdb
spec:
  # Chọn 1 trong 2:
  minAvailable: 2       # Ít nhất 2 Pods phải AVAILABLE
  # hoặc
  maxUnavailable: 1     # Tối đa 1 Pod có thể UNAVAILABLE

  selector:
    matchLabels:
      app: my-app       # Áp dụng cho Pods có label này
```

### minAvailable vs maxUnavailable

```
Deployment: 5 replicas, tất cả đang Running

Scenario A: minAvailable: 3
  → Có thể disrupt tối đa 2 Pods cùng lúc (5-3=2)
  → Drain node: nếu node chứa 3 Pods → chỉ drain 2 được, Pod thứ 3 bị block

Scenario B: maxUnavailable: 1
  → Chỉ 1 Pod được unavailable cùng lúc
  → Drain node: dù node có 5 Pods, chỉ evict 1 rồi chờ reschedule, rồi tiếp

Scenario C: minAvailable: "80%"
  → Với 5 replicas → 80% = 4 Pods phải available
  → Tối đa 1 Pod unavailable
```

### PDB và Rolling Update

```
Rolling Update Strategy:
  maxSurge: 1      → Cho phép có thêm 1 Pod (tổng 6 Pod tạm thời)
  maxUnavailable: 0 → Không cho phép Pod nào unavailable trong update

PDB: minAvailable: 2

Quá trình update với 3 replicas:
1. Tạo 1 Pod mới (v2) → Total: 4 pods (3 old + 1 new)
2. Terminate 1 Pod cũ → Total: 3 pods (2 old + 1 new) ✅ PDB satisfied
3. Tạo 1 Pod mới (v2) → Total: 4 pods (2 old + 2 new)
4. Terminate 1 Pod cũ → Total: 3 pods (1 old + 2 new) ✅
5. Tạo 1 Pod mới (v2) → Total: 4 pods (1 old + 3 new)
6. Terminate 1 Pod cũ → Total: 3 pods (0 old + 3 new) ✅
```

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Deploy ứng dụng HA (High Availability)

```bash
# Deploy ứng dụng với 3 replicas
kubectl apply -f manifests/deployment-ha-app.yaml

# Chờ tất cả pods running
kubectl rollout status deployment/ha-app

# Xem pods được phân bổ trên các nodes
kubectl get pods -l app=ha-app -o wide

# Expected: Pods trải đều trên nhiều nodes nhờ anti-affinity
```

---

### Step 2: Tạo PDB với minAvailable

```bash
# Tạo PDB đảm bảo luôn có ít nhất 2 Pods
kubectl apply -f manifests/pdb-ha-app.yaml

# Xem PDB đã tạo
kubectl get pdb

# Expected output:
# NAME         MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
# ha-app-pdb   2               N/A               1                     10s
#                                                ↑ Có thể disrupt 1 Pod (3-2=1)

# Xem chi tiết PDB
kubectl describe pdb ha-app-pdb
```

**Giải thích output:**
```
Name:             ha-app-pdb
Namespace:        default
Min available:    2
Max unavailable:  N/A
Selector:         app=ha-app

Status:
  Allowed disruptions:  1    ← Hiện tại có thể disrupt 1 pod
  Current:              3    ← Số pods hiện tại
  Desired:              2    ← Số pods tối thiểu (minAvailable)
  Total:                3    ← Tổng pods match selector
```

---

### Step 3: Test PDB với kubectl drain

```bash
# Xem pods đang chạy ở node nào
kubectl get pods -l app=ha-app -o wide

# Lấy tên node có ít nhất 1 pod ha-app
POD_NODE=$(kubectl get pods -l app=ha-app -o jsonpath='{.items[0].spec.nodeName}')
echo "Sẽ drain node: $POD_NODE"

# Đếm số pods ha-app trên node này
kubectl get pods -l app=ha-app -o wide | grep $POD_NODE | wc -l
```

**Test Case 1: Drain node có 1 Pod (sẽ được phép vì còn đủ minAvailable)**
```bash
# Drain node (--ignore-daemonsets để bỏ qua DaemonSet pods)
kubectl drain $POD_NODE \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --timeout=60s

# Theo dõi quá trình drain
kubectl get pods -l app=ha-app -o wide -w

# Sau drain: Pod từ node đó được reschedule sang node khác
# PDB được satisfied vì vẫn còn ≥ 2 Pods available
```

**Uncordon node sau drain:**
```bash
kubectl uncordon $POD_NODE
kubectl get nodes  # node trở lại Ready,SchedulingDisabled → Ready
```

**Test Case 2: Scale xuống còn 2 replicas rồi try drain**
```bash
# Scale xuống 2 replicas
kubectl scale deployment ha-app --replicas=2

# Xem pods hiện tại
kubectl get pods -l app=ha-app -o wide
kubectl get pdb ha-app-pdb
# ALLOWED DISRUPTIONS: 0 ← Không được disrupt Pod nào!

# Thử drain node (sẽ bị block bởi PDB!)
POD_NODE2=$(kubectl get pods -l app=ha-app -o jsonpath='{.items[0].spec.nodeName}')
kubectl drain $POD_NODE2 --ignore-daemonsets --delete-emptydir-data --timeout=30s

# Expected: Lỗi hoặc timeout vì PDB block!
# "Cannot evict pod as it would violate the pod's disruption budget."
```

```bash
# Scale lại 3 replicas
kubectl scale deployment ha-app --replicas=3

# Uncordon node nếu cần
kubectl uncordon $POD_NODE2
```

---

### Step 4: PDB với Percentage

```bash
# Tạo PDB với minAvailable: "80%"
kubectl apply -f manifests/pdb-percentage.yaml

# Với 5 replicas và minAvailable 80%:
# Available ≥ ceil(5 × 80%) = 4 pods
# ALLOWED DISRUPTIONS = 5 - 4 = 1

kubectl get pdb pdb-ha-app-percentage

# Scale deployment để test
kubectl scale deployment ha-app --replicas=5

# Xem PDB với 5 replicas
kubectl get pdb pdb-ha-app-percentage
# ALLOWED DISRUPTIONS: 1 (5 - 80% of 5 = 5-4 = 1)

kubectl scale deployment ha-app --replicas=10
kubectl get pdb pdb-ha-app-percentage
# ALLOWED DISRUPTIONS: 2 (10 - 80% of 10 = 10-8 = 2)
```

---

### Step 5: PDB và Rolling Update

```bash
# Đảm bảo ha-app có 3 replicas
kubectl scale deployment ha-app --replicas=3

# Xem PDB status
kubectl get pdb ha-app-pdb

# Trigger rolling update (đổi image tag)
kubectl set image deployment/ha-app ha-app=nginx:1.25-alpine

# Theo dõi rolling update + PDB interaction
watch -n 2 'kubectl get pods -l app=ha-app && echo "---" && kubectl get pdb ha-app-pdb'

# Trong quá trình update, PDB sẽ đảm bảo không có lúc nào
# số pods available xuống dưới 2
```

---

### Step 6: Xem PDB Events và Trạng thái

```bash
# Xem events liên quan đến PDB
kubectl get events --sort-by='.lastTimestamp' | grep -i "disrupt\|evict\|pdb"

# Xem PDB status chi tiết
kubectl describe pdb ha-app-pdb

# Xem disruption budget của pod cụ thể
kubectl get pod -l app=ha-app -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations}{"\n"}{end}'

# Kiểm tra PDB bằng dry-run eviction
kubectl get pod -l app=ha-app -o name | head -1 | xargs kubectl evict --dry-run=client 2>&1 || echo "Eviction would be blocked by PDB"
```

---

### Step 7: Simulate Production PDB Best Practices

```bash
# Scenario: Production deployment với strict PDB
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prod-api
  labels:
    app: prod-api
    tier: production
spec:
  replicas: 6
  selector:
    matchLabels:
      app: prod-api
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 2
      maxUnavailable: 0    # Zero downtime rolling update
  template:
    metadata:
      labels:
        app: prod-api
    spec:
      terminationGracePeriodSeconds: 30
      containers:
      - name: api
        image: nginx:1.25
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: prod-api-pdb
spec:
  maxUnavailable: 1    # Dùng maxUnavailable thay minAvailable
  selector:
    matchLabels:
      app: prod-api
EOF

kubectl get pdb prod-api-pdb
# ALLOWED DISRUPTIONS: 1 → Có thể evict 1 pod cùng lúc
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# 1. Xem tất cả PDBs
kubectl get pdb

# Expected:
# NAME                    MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS
# ha-app-pdb              2               N/A               1
# pdb-ha-app-percentage   80%             N/A               1

# 2. Kiểm tra PDB status
kubectl describe pdb ha-app-pdb | grep -A 10 "Status:"

# 3. Test eviction thủ công (không xóa pod thật)
kubectl get pods -l app=ha-app -o name | head -1

# 4. Verify drain bị block khi không đủ pods
kubectl scale deployment ha-app --replicas=2
kubectl get pdb ha-app-pdb
# ALLOWED DISRUPTIONS phải là 0
kubectl scale deployment ha-app --replicas=3  # Restore
```

**Checklist:**
- [ ] PDB được tạo và hiển thị ALLOWED DISRUPTIONS > 0
- [ ] `kubectl drain` bị block khi sẽ vi phạm PDB
- [ ] `kubectl drain` thành công khi có đủ pods available
- [ ] Rolling update hoạt động bình thường với PDB
- [ ] PDB với percentage hoạt động chính xác

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Uncordon tất cả nodes nếu có node bị cordon
kubectl uncordon --all 2>/dev/null || true

# Xóa tất cả resources
kubectl delete -f manifests/ --ignore-not-found
kubectl delete deployment prod-api --ignore-not-found
kubectl delete pdb prod-api-pdb --ignore-not-found

# Kiểm tra đã sạch
kubectl get pdb
kubectl get pods -l app=ha-app
```

---

## 💡 Tips & Gotchas

### ⚠️ Thường gặp

1. **PDB không block drain vì pods không có label match**
   ```bash
   # Kiểm tra selector của PDB
   kubectl get pdb -o yaml | grep -A 5 "selector:"
   # Kiểm tra labels của pods
   kubectl get pods --show-labels
   ```

2. **Drain timeout do PDB**
   ```bash
   # Kiểm tra ALLOWED DISRUPTIONS
   kubectl get pdb
   # Nếu = 0, phải scale up replicas trước hoặc xóa PDB tạm thời
   # Emergency bypass (KHÔNG khuyến khích production):
   kubectl delete pdb ha-app-pdb
   kubectl drain <node> ...
   kubectl apply -f manifests/pdb-ha-app.yaml  # Recreate sau drain
   ```

3. **PDB với StatefulSet cần chú ý thứ tự**
   ```bash
   # StatefulSet pods được đánh số: pod-0, pod-1, pod-2
   # PDB hoạt động theo disruption budget, không theo thứ tự
   # Nên test kỹ trước khi deploy StatefulSet + PDB lên production
   ```

4. **maxUnavailable: 0 kết hợp PDB có thể gây deadlock**
   ```bash
   # Deployment: maxUnavailable: 0 + PDB: minAvailable: all-replicas
   # → Rolling update sẽ bị stuck (không thể terminate pod cũ)
   # → Luôn để ALLOWED DISRUPTIONS ≥ 1
   ```

### 💡 Best Practices

- **Production**: Luôn có PDB cho mọi stateless/stateful deployment quan trọng
- **minAvailable** phù hợp khi biết số lượng Pod minimum cần thiết
- **maxUnavailable** phù hợp cho Rolling Update scenarios
- **`maxUnavailable: 1`** là setting an toàn nhất cho hầu hết production workloads
- Kết hợp PDB với **`terminationGracePeriodSeconds`** để graceful shutdown
- Không đặt `minAvailable` = số replicas (sẽ không drain được node bao giờ)
- Dùng `kubectl drain --timeout` khi drain node để tránh wait vô hạn

---

## 📚 Tham khảo (References)

- [Pod Disruption Budgets](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)
- [Specifying a Disruption Budget](https://kubernetes.io/docs/tasks/run-application/configure-pdb/)
- [Disruptions API](https://kubernetes.io/docs/reference/kubernetes-api/policy-resources/pod-disruption-budget-v1/)
- [kubectl drain documentation](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#drain)

---

## 🔗 Next Lab

➡️ **[Lab 24 — Custom Resource Definition (CRD) & Operator Pattern](../lab-24-crd-operator/README.md)**

Lab 24 sẽ khám phá cách **mở rộng Kubernetes API** với CRDs và hiểu pattern Operator — nền tảng của mọi production-grade Kubernetes tooling.
