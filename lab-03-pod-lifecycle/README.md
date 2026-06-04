# Lab 03 — Pod Lifecycle & YAML Manifests

## 🎯 Mục tiêu (Objectives)

Sau lab này, bạn sẽ có thể:
- Hiểu và mô tả được **Pod lifecycle** với đầy đủ các trạng thái
- Viết **Pod YAML manifest từ đầu**, hiểu rõ từng field
- So sánh cách tạo pod bằng **kubectl run** vs **YAML declarative**
- Thành thạo các lệnh **debug**: `logs`, `exec`, `describe`, `events`
- Phân biệt và chọn đúng **restart policy**: Always, OnFailure, Never

---

## 📋 Prerequisites

- Đã hoàn thành [Lab 02 — Namespace & Context](../lab-02-namespace-context/README.md)
- Namespace `dev` đã tạo (từ Lab 02), hoặc dùng `default`
- `kubectl` kết nối cluster thành công

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Pod Lifecycle — Trạng thái của một Pod

```
                          ┌───────────────────┐
                          │   Pod Created      │
                          │   (Scheduler       │
                          │    assigns Node)   │
                          └────────┬──────────┘
                                   │
                                   ▼
                          ┌───────────────────┐
                          │     Pending        │
                          │                   │
                          │  - Pulling image   │
                          │  - Waiting for     │
                          │    resources       │
                          │  - Init containers │
                          │    running         │
                          └────────┬──────────┘
                                   │
                    ┌──────────────┼──────────────┐
                    │              │              │
                    ▼              ▼              ▼
           ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
           │   Running    │ │   Succeeded  │ │    Failed    │
           │              │ │              │ │              │
           │ ≥1 container │ │ All containers│ │ ≥1 container │
           │ is running   │ │ exited with 0│ │ exited ≠ 0  │
           └──────┬───────┘ └──────────────┘ └──────────────┘
                  │
                  ▼
         ┌──────────────────┐
         │    Unknown       │
         │                  │
         │  Node lost comm  │
         │  with API server │
         └──────────────────┘

Container States (bên trong Pod):
  ┌──────────┐    ┌──────────┐    ┌──────────┐
  │ Waiting  │ -> │ Running  │ -> │Terminated│
  │          │    │          │    │          │
  │ Pulling  │    │ Started  │    │ Exit code│
  │ image... │    │ running  │    │ 0 or non0│
  └──────────┘    └──────────┘    └──────────┘
```

### Pod Conditions (Điều kiện):

| Condition | Ý nghĩa |
|-----------|---------|
| `PodScheduled` | Pod đã được assign vào một Node |
| `Initialized` | Tất cả init containers đã chạy xong |
| `ContainersReady` | Tất cả containers trong pod đã sẵn sàng |
| `Ready` | Pod sẵn sàng nhận traffic (readiness probe passed) |

### Restart Policies:

| Policy | Khi nào restart | Use case |
|--------|----------------|----------|
| `Always` | Luôn restart khi container thoát (bất kể exit code) | Web servers, long-running services |
| `OnFailure` | Chỉ restart khi exit code ≠ 0 | Batch jobs, data processing |
| `Never` | Không bao giờ restart | One-time tasks, debugging |

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Tạo Pod bằng kubectl run (Imperative)

```bash
# Cách nhanh nhất để chạy một pod
kubectl run nginx-quick --image=nginx:alpine

# Xem pod vừa tạo
kubectl get pods
kubectl get pods -w    # Watch mode

# Xem thông tin chi tiết hơn
kubectl get pods -o wide

# Tạo pod và chạy một lệnh (one-shot)
kubectl run busybox-test --image=busybox --restart=Never -- echo "Hello Kubernetes"

# Tạo pod với interactive shell
kubectl run -it busybox-shell --image=busybox --restart=Never -- sh
# Khi xong, gõ: exit

# Tạo pod và xóa ngay sau khi chạy xong (--rm)
kubectl run -it busybox-rm --image=busybox --restart=Never --rm -- wget -qO- http://nginx-quick

# Tạo YAML template từ kubectl run (không deploy)
kubectl run nginx-template --image=nginx:alpine --dry-run=client -o yaml
# Copy output này ra file để edit thêm
```

### Step 2: Viết Pod YAML từ đầu (Field by Field)

Hãy mở file `manifests/pod-nginx.yaml` và hiểu từng field:

```bash
# Apply pod từ YAML
kubectl apply -f manifests/pod-nginx.yaml -n dev

# Xem trạng thái
kubectl get pods -n dev
kubectl get pods -n dev -w   # Watch

# Khi pod Running, xem details
kubectl describe pod nginx-pod -n dev
```

**Giải thích cấu trúc Pod YAML (xem file pod-nginx.yaml):**

```yaml
apiVersion: v1          # API group: v1 là core group (pods, services, ...)
kind: Pod               # Loại resource
metadata:               # Thông tin định danh
  name: nginx-pod       # Tên pod - phải unique trong namespace
  namespace: dev        # Namespace chứa pod
  labels:               # Key-value pairs dùng để select/filter
    app: nginx          # Convention: 'app' label = tên app
    version: "1.0"      # Version tracking
  annotations:          # Metadata bổ sung, không dùng để select
    description: "..."  # Mô tả human-readable
spec:                   # Desired state của pod
  containers:           # List các containers (phải có ít nhất 1)
  - name: nginx         # Tên container (unique trong pod)
    image: nginx:alpine # Docker image (luôn pin version!)
    ports:              # Documenting ports (không ảnh hưởng networking)
    - containerPort: 80
    resources:          # QUAN TRỌNG: luôn set limits
      requests:         # Minimum resources cần để schedule
        cpu: "100m"     # 100 millicores = 0.1 CPU core
        memory: "128Mi"
      limits:           # Maximum resources container có thể dùng
        cpu: "200m"
        memory: "256Mi"
    livenessProbe:      # Kubernetes check container còn "sống" không
      httpGet:
        path: /
        port: 80
      initialDelaySeconds: 10  # Chờ 10s trước khi probe lần đầu
      periodSeconds: 30         # Probe mỗi 30s
    readinessProbe:     # Kubernetes check container sẵn sàng nhận traffic chưa
      httpGet:
        path: /
        port: 80
      initialDelaySeconds: 5
      periodSeconds: 10
```

### Step 3: Apply và quan sát Pod States

```bash
# Apply tất cả pods trong lab
kubectl apply -f manifests/pod-nginx.yaml -n dev
kubectl apply -f manifests/pod-busybox-restart.yaml -n dev
kubectl apply -f manifests/pod-debug.yaml -n dev

# Quan sát trạng thái pod
kubectl get pods -n dev

# Output mẫu:
# NAME                    READY   STATUS      RESTARTS   AGE
# nginx-pod               1/1     Running     0          2m
# busybox-onfailure       0/1     Completed   0          1m
# debug-pod               1/1     Running     0          30s

# Xem chi tiết tất cả pods
kubectl describe pods -n dev
```

### Step 4: Debugging với kubectl logs

```bash
# Xem logs của pod nginx
kubectl logs nginx-pod -n dev

# Follow logs (real-time, như tail -f)
kubectl logs nginx-pod -n dev -f

# Xem 20 dòng cuối
kubectl logs nginx-pod -n dev --tail=20

# Xem logs trong 30 phút gần nhất
kubectl logs nginx-pod -n dev --since=30m

# Xem logs của container cụ thể (pod multi-container)
kubectl logs <pod-name> -c <container-name> -n dev

# Xem logs của pod đã crash (lần chạy trước)
kubectl logs <pod-name> -n dev --previous

# Xem logs từ tất cả pods có label cụ thể
kubectl logs -l app=nginx -n dev --max-log-requests=10

# Combine: follow + tail
kubectl logs nginx-pod -n dev -f --tail=50
```

### Step 5: Debugging với kubectl exec

```bash
# Mở interactive shell trong pod
kubectl exec -it nginx-pod -n dev -- /bin/sh

# Trong shell, thử các lệnh:
# ls /etc/nginx/
# cat /etc/nginx/nginx.conf
# wget -qO- http://localhost/
# exit

# Chạy lệnh không interactive
kubectl exec nginx-pod -n dev -- ls /etc/nginx/
kubectl exec nginx-pod -n dev -- cat /etc/nginx/nginx.conf
kubectl exec nginx-pod -n dev -- env

# Xem processes trong container
kubectl exec nginx-pod -n dev -- ps aux

# Kiểm tra network
kubectl exec nginx-pod -n dev -- wget -qO- http://localhost/

# Copy file từ/vào container
kubectl cp nginx-pod:/etc/nginx/nginx.conf ./nginx.conf -n dev
kubectl cp ./test-file.txt nginx-pod:/tmp/ -n dev
```

### Step 6: Debugging với kubectl describe

```bash
# Describe pod - thông tin đầy đủ nhất
kubectl describe pod nginx-pod -n dev

# Chú ý các phần quan trọng trong describe output:
# - Status: Running/Pending/Failed
# - IP: Pod IP address
# - Node: Pod đang chạy trên node nào
# - Containers: trạng thái từng container
# - Conditions: PodScheduled, Initialized, Ready, ContainersReady
# - Volumes: volumes được mount
# - Events: ← ĐÂY LÀ PHẦN QUAN TRỌNG NHẤT KHI DEBUG

# Xem chỉ phần Events
kubectl describe pod nginx-pod -n dev | grep -A 20 "Events:"

# Các lỗi thường gặp trong Events:
# - ErrImagePull / ImagePullBackOff: Không pull được image
# - OOMKilled: Pod bị kill vì dùng quá Memory limit
# - CrashLoopBackOff: Container liên tục crash và restart
# - Pending: Không đủ resources trên node để schedule
```

### Step 7: Xem Events trong cluster

```bash
# Xem tất cả events trong namespace
kubectl get events -n dev

# Sort theo thời gian (mới nhất cuối cùng)
kubectl get events -n dev --sort-by='.lastTimestamp'

# Chỉ xem Warning events
kubectl get events -n dev --field-selector type=Warning

# Xem events của một pod cụ thể
kubectl get events -n dev --field-selector involvedObject.name=nginx-pod

# Format output
kubectl get events -n dev -o wide
```

### Step 8: Quan sát Restart Policies

```bash
# Policy: OnFailure - restart khi exit code != 0
kubectl apply -f manifests/pod-busybox-restart.yaml -n dev
kubectl get pods -n dev -w

# Xem restart count
kubectl get pods busybox-onfailure -n dev

# Policy: Never - không restart
kubectl run never-restart \
  --image=busybox \
  --restart=Never \
  -n dev \
  -- sh -c "echo 'Task done'; exit 0"

# Pod sẽ ở trạng thái Completed
kubectl get pods never-restart -n dev

# Test fail case - exit với code != 0
kubectl run fail-never \
  --image=busybox \
  --restart=Never \
  -n dev \
  -- sh -c "exit 1"

# Pod sẽ ở trạng thái Error (không restart)
kubectl get pods fail-never -n dev
```

### Step 9: Port-forward để test pod

```bash
# Port forward local port 8080 -> pod port 80
kubectl port-forward pod/nginx-pod 8080:80 -n dev

# Trong terminal khác:
curl http://localhost:8080
# hoặc mở browser: http://localhost:8080

# Port forward với địa chỉ binding cụ thể
kubectl port-forward pod/nginx-pod 0.0.0.0:8080:80 -n dev

# Ctrl+C để dừng port-forward
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# 1. Pods đang chạy
kubectl get pods -n dev
# ✅ nginx-pod phải ở trạng thái: 1/1 Running

# 2. Liveness và Readiness probes
kubectl describe pod nginx-pod -n dev | grep -E "Liveness|Readiness"
# ✅ Phải thấy probe configuration

# 3. Logs có nội dung
kubectl logs nginx-pod -n dev
# ✅ Phải thấy nginx access log hoặc startup logs

# 4. Exec vào pod hoạt động
kubectl exec nginx-pod -n dev -- nginx -v
# ✅ Phải in ra nginx version

# 5. Pod IP được assign
kubectl get pod nginx-pod -n dev -o jsonpath='{.status.podIP}'
# ✅ Phải có IP address (VD: 10.244.0.5)

# 6. Restart policy đúng
kubectl get pod nginx-pod -n dev -o jsonpath='{.spec.restartPolicy}'
# ✅ Phải là: Always

# 7. Resource limits được set
kubectl get pod nginx-pod -n dev -o jsonpath='{.spec.containers[0].resources}'
# ✅ Phải thấy requests và limits
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xóa tất cả pods đã tạo trong lab này
kubectl delete -f manifests/pod-nginx.yaml -n dev --ignore-not-found
kubectl delete -f manifests/pod-busybox-restart.yaml -n dev --ignore-not-found
kubectl delete -f manifests/pod-debug.yaml -n dev --ignore-not-found

# Xóa pods tạo bằng imperative commands
kubectl delete pod nginx-quick --ignore-not-found
kubectl delete pod busybox-test -n dev --ignore-not-found
kubectl delete pod never-restart -n dev --ignore-not-found
kubectl delete pod fail-never -n dev --ignore-not-found

# Verify
kubectl get pods -n dev
# ✅ Không còn pod nào
```

---

## 💡 Tips & Gotchas

### ⚠️ Gotcha 1: CrashLoopBackOff

```bash
# Pod cứ crash và restart -> trạng thái CrashLoopBackOff
# Debug:
kubectl logs <pod> --previous   # Xem logs lần crash TRƯỚC
kubectl describe pod <pod>       # Xem events: OOMKilled? Exit code?

# Tăng time để debug (hack: override command)
kubectl run debug-crash --image=broken-image --command -- sleep infinity
```

### ⚠️ Gotcha 2: ImagePullBackOff

```bash
# Không pull được image
kubectl describe pod <pod> | grep -A5 "Events:"
# Thường do:
# - Sai tên image hoặc tag
# - Private registry chưa có credentials
# - Rate limit (Docker Hub)

# Fix: kiểm tra image name
docker pull <image>:<tag>   # Test locally
```

### ⚠️ Gotcha 3: Pending pod

```bash
# Pod ở Pending -> không được schedule
kubectl describe pod <pod> | grep "Events:" -A10
# Nguyên nhân thường gặp:
# - Không đủ CPU/Memory trên bất kỳ node nào
# - PVC chưa được bound
# - Node selector không match
# - Taint/Toleration không match

kubectl describe nodes | grep -A 5 "Allocated resources"
```

### 💡 Tip: Luôn set Resource Limits!

```yaml
resources:
  requests:      # Minimum để schedule
    cpu: "100m"
    memory: "128Mi"
  limits:        # Maximum để tránh "noisy neighbor"
    cpu: "500m"
    memory: "512Mi"
```

> Không set limits → container có thể dùng hết tài nguyên node → ảnh hưởng các pod khác!

### 💡 Tip: Sử dụng Labels có ý nghĩa

```yaml
labels:
  app: nginx                  # Tên application
  version: "1.25"             # Version của app
  environment: dev            # Môi trường
  tier: frontend              # Tier (frontend/backend/db)
  managed-by: kubectl         # Ai/tool nào quản lý
```

### 💡 Tip: Debug pod không start được

```bash
# Workflow debug nhanh:
kubectl get pods <pod>          # 1. Xem STATUS
kubectl describe pod <pod>      # 2. Xem Events
kubectl logs <pod>              # 3. Xem application logs
kubectl logs <pod> --previous   # 4. Nếu đã crash
kubectl exec -it <pod> -- sh   # 5. Vào bên trong nếu cần
```

---

## 📚 Tham khảo (References)

- [Pod Lifecycle - Kubernetes Docs](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
- [Pod YAML Reference](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/)
- [kubectl logs](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#logs)
- [Configure Liveness, Readiness Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

---

## 🔗 Next Lab

➡️ **[Lab 04 — Multi-container Pod & Init Container](../lab-04-multicontainer-pod/README.md)**

Lab tiếp theo sẽ khám phá các **design patterns** cho Pod phức tạp hơn: Sidecar, Ambassador, Adapter và Init Containers — những patterns được dùng rộng rãi trong production.
