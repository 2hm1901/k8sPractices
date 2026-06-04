# Lab 05 — ReplicaSet & Self-healing

## 🎯 Mục tiêu (Objectives)

Sau lab này bạn sẽ hiểu và làm được:
- Tạo và cấu hình **ReplicaSet** với `replicas`, `selector`, `template`
- Hiểu sâu về **Label Selectors** (`matchLabels`, `matchExpressions`)
- Chứng minh **self-healing**: Kubernetes tự động restart pod khi bị xoá
- **Scale** ReplicaSet thủ công (scale up / scale down)
- Phân biệt sự khác biệt giữa **ReplicaSet** và **Deployment**

---

## 📋 Prerequisites

- Đã hoàn thành Lab 01–04
- Có cluster Kubernetes đang chạy (`minikube`, `kind`, hoặc cloud cluster)
- `kubectl` đã được cấu hình và kết nối cluster

```bash
# Kiểm tra cluster
kubectl cluster-info
kubectl get nodes
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### ReplicaSet là gì?

**ReplicaSet** đảm bảo rằng một số lượng bản sao (replicas) của Pod luôn chạy tại bất kỳ thời điểm nào. Nếu một Pod bị crash hoặc bị xoá, ReplicaSet sẽ tự động tạo Pod mới để bù vào.

```
┌─────────────────────────────────────────────────────┐
│                   ReplicaSet                        │
│                                                     │
│  spec.replicas: 3                                   │
│  spec.selector:                                     │
│    matchLabels:                                     │
│      app: nginx                                     │
│                                                     │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐            │
│  │  Pod-1  │  │  Pod-2  │  │  Pod-3  │            │
│  │app:nginx│  │app:nginx│  │app:nginx│            │
│  └─────────┘  └─────────┘  └─────────┘            │
└─────────────────────────────────────────────────────┘

Nếu Pod-2 bị xoá:

  ┌─────────┐  ✗ DELETED  ┌─────────┐
  │  Pod-1  │             │  Pod-3  │
  └─────────┘             └─────────┘
          ↓ ReplicaSet phát hiện chỉ còn 2 pods
  ┌─────────┐  ┌─────────┐  ┌─────────┐
  │  Pod-1  │  │  Pod-3  │  │  Pod-4  │ ← Pod mới được tạo
  └─────────┘  └─────────┘  └─────────┘
```

### Ba thành phần chính của ReplicaSet Spec

| Trường | Mô tả |
|--------|-------|
| `spec.replicas` | Số lượng pod mong muốn |
| `spec.selector` | Label selector để tìm pod thuộc RS |
| `spec.template` | Template để tạo pod mới |

### Label Selectors

**Equality-based** (dùng `matchLabels`):
```yaml
selector:
  matchLabels:
    app: nginx
    env: prod
```

**Set-based** (dùng `matchExpressions`):
```yaml
selector:
  matchExpressions:
    - key: app
      operator: In        # In, NotIn, Exists, DoesNotExist
      values: [nginx, apache]
    - key: env
      operator: NotIn
      values: [dev]
```

### ReplicaSet vs Deployment

| Tính năng | ReplicaSet | Deployment |
|-----------|-----------|------------|
| Đảm bảo số lượng pod | ✅ | ✅ (thông qua RS) |
| Rolling Update | ❌ | ✅ |
| Rollback | ❌ | ✅ |
| Revision history | ❌ | ✅ |
| Sử dụng trực tiếp | Hiếm | Thường xuyên |

> **Lưu ý**: Trong thực tế, bạn hầu như không bao giờ tạo ReplicaSet trực tiếp. Deployment sẽ quản lý ReplicaSet cho bạn.

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Tạo namespace cho lab

```bash
kubectl create namespace lab05
kubectl config set-context --current --namespace=lab05
```

### Step 2: Tạo ReplicaSet cơ bản

```bash
kubectl apply -f manifests/replicaset-nginx.yaml
```

Kiểm tra ngay sau khi tạo:

```bash
# Xem ReplicaSet
kubectl get replicaset -n lab05
# Hoặc viết tắt
kubectl get rs -n lab05

# Output mong đợi:
# NAME              DESIRED   CURRENT   READY   AGE
# nginx-replicaset  3         3         3       30s
```

Xem chi tiết ReplicaSet:
```bash
kubectl describe rs nginx-replicaset -n lab05
```

Xem các Pods được tạo bởi ReplicaSet:
```bash
kubectl get pods -n lab05 --show-labels
# Chú ý: Tên pod có suffix ngẫu nhiên (e.g., nginx-replicaset-x7k9p)
```

### Step 3: Demo Self-Healing — Xoá Pod và quan sát

Mở **hai terminal**:

**Terminal 1** – Watch pods liên tục:
```bash
kubectl get pods -n lab05 -w
```

**Terminal 2** – Xoá một pod:
```bash
# Lấy tên pod đầu tiên
POD_NAME=$(kubectl get pods -n lab05 -o jsonpath='{.items[0].metadata.name}')
echo "Xoá pod: $POD_NAME"

kubectl delete pod $POD_NAME -n lab05
```

**Quan sát Terminal 1** – bạn sẽ thấy:
```
NAME                       READY   STATUS        RESTARTS   AGE
nginx-replicaset-x7k9p     1/1     Running       0          2m
nginx-replicaset-m3nq1     1/1     Running       0          2m
nginx-replicaset-p8wvz     1/1     Running       0          2m
nginx-replicaset-x7k9p     1/1     Terminating   0          2m   ← Pod bị xoá
nginx-replicaset-r2ght     0/1     Pending       0          0s   ← Pod mới ngay lập tức!
nginx-replicaset-r2ght     0/1     ContainerCreating  0    0s
nginx-replicaset-r2ght     1/1     Running       0          3s
```

> 🎯 **Self-healing** đang hoạt động! Kubernetes phát hiện số pod < 3 và ngay lập tức tạo pod mới.

### Step 4: Xoá nhiều pod cùng lúc

```bash
# Xoá TẤT CẢ pods cùng lúc bằng label selector
kubectl delete pods -l app=nginx -n lab05

# Xem pods ngay sau đó
kubectl get pods -n lab05
# Kubernetes sẽ tạo lại đủ 3 pod!
```

### Step 5: Manual Scaling — Scale Up

```bash
# Scale lên 5 replicas (imperative)
kubectl scale rs nginx-replicaset --replicas=5 -n lab05

# Kiểm tra
kubectl get rs nginx-replicaset -n lab05
kubectl get pods -n lab05
```

Hoặc edit trực tiếp YAML (declarative):
```bash
kubectl edit rs nginx-replicaset -n lab05
# Tìm "replicas: 3" → đổi thành "replicas: 5"
```

Hoặc patch:
```bash
kubectl patch rs nginx-replicaset -n lab05 -p '{"spec":{"replicas":5}}'
```

### Step 6: Manual Scaling — Scale Down

```bash
# Scale xuống 2 replicas
kubectl scale rs nginx-replicaset --replicas=2 -n lab05

# Quan sát pods bị terminate
kubectl get pods -n lab05 -w
```

### Step 7: Kiểm tra ownership (Pod → ReplicaSet)

```bash
# Xem ownerReference của pod
POD_NAME=$(kubectl get pods -n lab05 -o jsonpath='{.items[0].metadata.name}')
kubectl get pod $POD_NAME -n lab05 -o jsonpath='{.metadata.ownerReferences}' | python3 -m json.tool
```

Output sẽ cho thấy pod "thuộc sở hữu" của ReplicaSet:
```json
[
  {
    "apiVersion": "apps/v1",
    "kind": "ReplicaSet",
    "name": "nginx-replicaset",
    "uid": "...",
    "controller": true,
    "blockOwnerDeletion": true
  }
]
```

### Step 8: Tạo ReplicaSet với Custom Labels và matchExpressions

```bash
kubectl apply -f manifests/replicaset-custom-label.yaml

kubectl get rs -n lab05
kubectl get pods -n lab05 --show-labels
```

### Step 9: Thử nghiệm "Pod adoption" — Tạo Pod thủ công với label khớp

```bash
# Tạo pod thủ công với label khớp với selector của RS
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: manual-pod
  namespace: lab05
  labels:
    app: nginx-custom
    tier: frontend
spec:
  containers:
  - name: nginx
    image: nginx:1.21
EOF

# Xem điều gì xảy ra
kubectl get pods -n lab05
# Pod thủ công có thể bị TERMINATE nếu RS đã đủ replicas!
```

> 💡 **Lưu ý thú vị**: ReplicaSet sẽ "nhận nuôi" (adopt) pod thủ công nếu nó khớp với selector VÀ RS chưa đủ số replicas. Ngược lại, nếu đã đủ replicas, pod sẽ bị terminate.

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# 1. Kiểm tra ReplicaSet đang chạy đúng số replicas
kubectl get rs -n lab05

# 2. Kiểm tra tất cả pods đang Running
kubectl get pods -n lab05

# 3. Kiểm tra events của ReplicaSet
kubectl describe rs nginx-replicaset -n lab05 | grep -A 20 "Events:"

# 4. Kiểm tra labels của pods
kubectl get pods -n lab05 --show-labels

# 5. Dùng label selector để filter pods
kubectl get pods -n lab05 -l app=nginx

# 6. Tóm tắt: Xem tất cả resources trong namespace
kubectl get all -n lab05
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xoá toàn bộ resources trong namespace
kubectl delete ns lab05

# Hoặc xoá từng resource
kubectl delete rs nginx-replicaset nginx-custom-rs -n lab05

# Reset namespace về default
kubectl config set-context --current --namespace=default
```

---

## 💡 Tips & Gotchas

1. **Selector phải khớp với template labels**: `spec.selector.matchLabels` phải là subset của `spec.template.metadata.labels`. Nếu không, Kubernetes sẽ reject khi apply.

2. **Selector là immutable**: Sau khi tạo ReplicaSet, bạn **không thể thay đổi** `spec.selector`. Phải xoá và tạo lại.

3. **Orphaned pods**: Nếu xoá ReplicaSet với `--cascade=orphan`, các pods sẽ tiếp tục chạy nhưng không còn được quản lý.
   ```bash
   kubectl delete rs nginx-replicaset --cascade=orphan -n lab05
   ```

4. **Dùng Deployment thay vì RS trực tiếp**: Trong production, luôn dùng Deployment. RS chỉ nên dùng khi bạn cần kiểm soát hoàn toàn update strategy.

5. **ResourceVersion conflict**: Khi scale, nếu bị lỗi `resourceVersion conflict`, thử lại sau vài giây.

---

## 📚 Tham khảo (References)

- [ReplicaSet | Kubernetes Docs](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/)
- [Labels and Selectors](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
- [kubectl scale reference](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)

---

## 🔗 Next Lab

➡️ [Lab 06 — Deployment & Rolling Update](../lab-06-deployment/README.md)
