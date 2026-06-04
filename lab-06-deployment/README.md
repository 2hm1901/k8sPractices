# Lab 06 — Deployment & Rolling Update

## 🎯 Mục tiêu (Objectives)

Sau lab này bạn sẽ hiểu và làm được:
- Hiểu cách **Deployment** quản lý **ReplicaSets** (tạo RS mới khi update)
- Cấu hình **Rolling Update** strategy với `maxSurge` và `maxUnavailable`
- Thực hiện **rollout** (deploy phiên bản mới) và quan sát quá trình
- **Rollback** về phiên bản trước với `kubectl rollout undo`
- Xem **rollout history** và rollback về revision cụ thể
- **Pause và resume** rollout để kiểm soát quá trình deploy
- Hiểu khái niệm **Blue/Green deployment**

---

## 📋 Prerequisites

- Đã hoàn thành Lab 05 (ReplicaSet)
- Cluster Kubernetes đang hoạt động
- Hiểu cơ bản về Pod và ReplicaSet

```bash
kubectl cluster-info
kubectl get nodes
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Deployment quản lý ReplicaSet như thế nào?

```
Deployment
    │
    ├── ReplicaSet v1 (nginx:1.21) — replicas: 0 (cũ, đã scale down)
    │       └── (không còn pod nào)
    │
    └── ReplicaSet v2 (nginx:1.22) — replicas: 3 (hiện tại)
            ├── Pod-1
            ├── Pod-2
            └── Pod-3

Mỗi lần update image/config → Deployment tạo ReplicaSet mới
```

### Rolling Update Strategy

```
Cấu hình:
  maxSurge: 1          → Cho phép tối đa 1 pod THÊM vào so với desired
  maxUnavailable: 0    → Không cho phép pod nào bị DOWN trong quá trình update

Timeline (desired=3):

Thời điểm 1 (Ban đầu):    [v1] [v1] [v1]               (3 pods running)
Thời điểm 2 (Start):      [v1] [v1] [v1] [v2]          (surge 1 pod mới)
Thời điểm 3 (Kill v1):    [v1] [v1] [v2]               (terminate 1 v1)
Thời điểm 4 (Add v2):     [v1] [v1] [v2] [v2]          (surge 1 pod mới)
Thời điểm 5 (Kill v1):    [v1] [v2] [v2]               (terminate 1 v1)
Thời điểm 6 (Add v2):     [v1] [v2] [v2] [v2]          (surge 1 pod mới)
Thời điểm 7 (Kill v1):    [v2] [v2] [v2]               (hoàn thành!)

→ Không bao giờ có ít hơn 3 pods (zero downtime!)
```

### Các Update Strategy

| Strategy | Mô tả | Use case |
|----------|-------|----------|
| `RollingUpdate` | Thay thế dần từng pod | Production (zero downtime) |
| `Recreate` | Xoá toàn bộ → tạo mới | Dev, hoặc khi không thể chạy 2 version song song |

### Blue/Green Deployment (Concept)

```
                    ┌─────────────────┐
User Traffic ──────►│   Service       │
                    │  selector:      │
                    │   color: blue   │──────► Blue Deployment (v1)
                    └─────────────────┘        (active)

                                               Green Deployment (v2)
                                               (ready, not receiving traffic)

Để switch: đổi Service selector sang color: green
```

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Tạo namespace và apply Deployment v1

```bash
kubectl create namespace lab06
kubectl config set-context --current --namespace=lab06

# Apply Deployment phiên bản 1 (nginx:1.21)
kubectl apply -f manifests/deployment-nginx.yaml
```

Quan sát quá trình rollout:
```bash
# Watch rollout status
kubectl rollout status deployment/nginx-deployment -n lab06

# Output:
# Waiting for deployment "nginx-deployment" rollout to finish: 0 of 3 updated replicas are available...
# Waiting for deployment "nginx-deployment" rollout to finish: 1 of 3 updated replicas are available...
# Waiting for deployment "nginx-deployment" rollout to finish: 2 of 3 updated replicas are available...
# deployment "nginx-deployment" successfully rolled out
```

```bash
# Xem Deployment
kubectl get deployment nginx-deployment -n lab06
# NAME               READY   UP-TO-DATE   AVAILABLE   AGE
# nginx-deployment   3/3     3            3           30s

# Xem ReplicaSet được tạo bởi Deployment
kubectl get replicaset -n lab06
# NAME                         DESIRED   CURRENT   READY
# nginx-deployment-7d6b5c8f9   3         3         3

# Xem tất cả pods
kubectl get pods -n lab06 --show-labels
```

### Step 2: Xem rollout history

```bash
kubectl rollout history deployment/nginx-deployment -n lab06
# REVISION  CHANGE-CAUSE
# 1         <none>
```

> 💡 **CHANGE-CAUSE** là `<none>` vì ta chưa dùng `--record` hoặc annotation. Thêm annotation để ghi lý do:

```bash
kubectl annotate deployment nginx-deployment kubernetes.io/change-cause="Initial deployment with nginx:1.21" -n lab06

kubectl rollout history deployment/nginx-deployment -n lab06
# REVISION  CHANGE-CAUSE
# 1         Initial deployment with nginx:1.21
```

### Step 3: Rolling Update lên phiên bản mới (v2)

**Mở Terminal 1** — Watch pods liên tục:
```bash
kubectl get pods -n lab06 -w
```

**Terminal 2** — Apply Deployment v2:
```bash
kubectl apply -f manifests/deployment-v2.yaml
```

Hoặc update image trực tiếp:
```bash
kubectl set image deployment/nginx-deployment nginx=nginx:1.22-alpine -n lab06
```

Thêm annotation cho revision mới:
```bash
kubectl annotate deployment nginx-deployment kubernetes.io/change-cause="Update to nginx:1.22-alpine" -n lab06
```

Quan sát **Terminal 1**:
```
NAME                             READY   STATUS              RESTARTS
nginx-deployment-7d6b5c8f9-abc   1/1     Running             0
nginx-deployment-7d6b5c8f9-def   1/1     Running             0
nginx-deployment-7d6b5c8f9-ghi   1/1     Running             0
nginx-deployment-9f8e7d6c5-xyz   0/1     Pending             0    ← Pod v2 tạo mới
nginx-deployment-9f8e7d6c5-xyz   0/1     ContainerCreating   0
nginx-deployment-9f8e7d6c5-xyz   1/1     Running             0    ← Pod v2 Ready
nginx-deployment-7d6b5c8f9-abc   1/1     Terminating         0    ← Pod v1 bị xoá
...
```

### Step 4: Xem rollout history sau khi update

```bash
kubectl rollout history deployment/nginx-deployment -n lab06
# REVISION  CHANGE-CAUSE
# 1         Initial deployment with nginx:1.21
# 2         Update to nginx:1.22-alpine

# Xem chi tiết revision cụ thể
kubectl rollout history deployment/nginx-deployment --revision=1 -n lab06
kubectl rollout history deployment/nginx-deployment --revision=2 -n lab06
```

Xem ReplicaSets — sẽ thấy 2 RS (v1 scale down, v2 scale up):
```bash
kubectl get rs -n lab06
# NAME                          DESIRED   CURRENT   READY
# nginx-deployment-7d6b5c8f9    0         0         0     ← RS v1 (scale down)
# nginx-deployment-9f8e7d6c5    3         3         3     ← RS v2 (active)
```

### Step 5: Rollback về phiên bản trước

```bash
# Rollback về revision ngay trước đó (revision 1)
kubectl rollout undo deployment/nginx-deployment -n lab06

# Xem status rollback
kubectl rollout status deployment/nginx-deployment -n lab06

# Xem history sau rollback
kubectl rollout history deployment/nginx-deployment -n lab06
# REVISION  CHANGE-CAUSE
# 2         Update to nginx:1.22-alpine
# 3         Initial deployment with nginx:1.21  ← Revision cũ thành revision mới nhất
```

Rollback về revision cụ thể:
```bash
# Rollback về revision 2
kubectl rollout undo deployment/nginx-deployment --to-revision=2 -n lab06
```

### Step 6: Pause và Resume Rollout

Tính năng này hữu ích khi bạn muốn:
- Deploy từng phần để kiểm tra (canary-like)
- Tạm dừng khi phát hiện vấn đề

```bash
# Bắt đầu rollout, rồi PAUSE ngay
kubectl set image deployment/nginx-deployment nginx=nginx:1.23-alpine -n lab06
kubectl rollout pause deployment/nginx-deployment -n lab06

# Kiểm tra — rollout đang bị pause
kubectl rollout status deployment/nginx-deployment -n lab06
# Waiting for deployment "nginx-deployment" rollout to finish: 1 out of 3 new replicas have been updated...
# (Sẽ không tiếp tục cho đến khi resume)

# Xem trạng thái pods — chỉ có 1 pod được update
kubectl get pods -n lab06 --show-labels

# Nếu OK → Resume
kubectl rollout resume deployment/nginx-deployment -n lab06
kubectl rollout status deployment/nginx-deployment -n lab06
```

### Step 7: Thử nghiệm Recreate Strategy

```bash
# Tạm thời patch deployment sang strategy Recreate
kubectl patch deployment nginx-deployment -n lab06 -p '
{
  "spec": {
    "strategy": {
      "type": "Recreate"
    }
  }
}'

# Update image
kubectl set image deployment/nginx-deployment nginx=nginx:1.21-alpine -n lab06

# Watch: Tất cả pods v1 bị xoá TRƯỚC, sau đó mới tạo pods mới
kubectl get pods -n lab06 -w
# → Có khoảng downtime ngắn!
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# 1. Kiểm tra Deployment
kubectl get deployment nginx-deployment -n lab06 -o wide

# 2. Kiểm tra rollout history
kubectl rollout history deployment/nginx-deployment -n lab06

# 3. Kiểm tra ReplicaSets (cả active và inactive)
kubectl get rs -n lab06

# 4. Kiểm tra image đang chạy
kubectl get pods -n lab06 -o jsonpath='{.items[*].spec.containers[0].image}'

# 5. Xem events của Deployment
kubectl describe deployment nginx-deployment -n lab06 | grep -A 30 "Events:"

# 6. Tổng quan tất cả resources
kubectl get all -n lab06
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xoá toàn bộ namespace (xoá tất cả resources)
kubectl delete namespace lab06

# Reset namespace
kubectl config set-context --current --namespace=default
```

---

## 💡 Tips & Gotchas

1. **`revisionHistoryLimit`**: Deployment mặc định giữ 10 revision cũ (ReplicaSets). Giảm xuống để tiết kiệm resources:
   ```yaml
   spec:
     revisionHistoryLimit: 3
   ```

2. **`maxSurge` và `maxUnavailable` có thể dùng % hoặc số nguyên**:
   ```yaml
   maxSurge: 25%        # 25% of desired replicas
   maxUnavailable: 1    # absolute number
   ```

3. **Deployment không rollback config của volumes**: `rollout undo` chỉ rollback image, không rollback ConfigMap hay Secret được reference.

4. **`kubectl set image` là cách nhanh nhất** để update image mà không cần sửa YAML.

5. **Deployment bị "stuck"?** Kiểm tra:
   ```bash
   kubectl rollout status deployment/nginx-deployment -n lab06
   kubectl describe deployment nginx-deployment -n lab06
   kubectl get events -n lab06 --sort-by='.lastTimestamp'
   ```

6. **`minReadySeconds`**: Thêm vào spec để đảm bảo pod ổn định trước khi tiếp tục rollout:
   ```yaml
   spec:
     minReadySeconds: 10  # Chờ 10 giây sau khi pod Ready
   ```

---

## 📚 Tham khảo (References)

- [Deployments | Kubernetes Docs](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Rolling Update Strategy](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-update-deployment)
- [kubectl rollout](https://kubernetes.io/docs/reference/kubectl/cheatsheet/#updating-resources)

---

## 🔗 Next Lab

➡️ [Lab 07 — DaemonSet & Static Pod](../lab-07-daemonset/README.md)
