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
# busybox-onfailure       0/1     CrashLoopBackOff  2    1m
# busybox-completed       0/1     Completed   0          1m
# busybox-never-restart   0/1     Error       0          1m
# debug-pod               1/1     Running     0          30s

# Xem chi tiết tất cả pods
kubectl describe pods -n dev
```

### Step 4: Debugging workflow - nhìn triệu chứng trước, chọn lệnh sau

Khi pod không chạy đúng, đừng chạy lệnh ngẫu nhiên. Hãy đi theo thứ tự này:

| Câu hỏi cần trả lời | Lệnh nên chạy | Vì sao |
|---------------------|---------------|--------|
| Pod đang ở trạng thái gì? | `kubectl get pods -n dev` | Xác định hướng debug: `Pending`, `Running`, `Error`, `CrashLoopBackOff`, `ImagePullBackOff` |
| Kubernetes đã làm gì với pod? | `kubectl describe pod <pod> -n dev` | Xem scheduling, pull image, probe, restart, exit code và Events |
| App/container in ra lỗi gì? | `kubectl logs <pod> -n dev` | Xem lỗi từ process bên trong container |
| Container đã crash và restart chưa? | `kubectl logs <pod> -n dev --previous` | Lấy log của lần chạy trước, vì lần hiện tại có thể vừa restart |
| Cần kiểm tra bên trong container? | `kubectl exec -it <pod> -n dev -- sh` | Chỉ dùng khi container còn đang Running |
| Có nhiều pod hoặc lỗi đã trôi mất trong describe? | `kubectl get events -n dev --sort-by='.lastTimestamp'` | Xem timeline sự kiện trong namespace |

> Quy tắc nhớ nhanh: `get` để biết tình trạng, `describe` để biết Kubernetes đang gặp gì, `logs` để biết app nói gì, `exec` để kiểm tra bên trong container.

### Step 5: Debugging với `kubectl describe`

`describe` là lệnh đầu tiên nên chạy khi pod không vào trạng thái mong muốn. Nó trả lời câu hỏi: "Kubernetes có tạo, schedule, pull image, start container và probe pod thành công không?"

```bash
# Xem trạng thái tổng quan trước
kubectl get pods -n dev

# Describe pod - thông tin đầy đủ nhất từ Kubernetes
kubectl describe pod nginx-pod -n dev
```

Khi đọc output, tập trung vào các phần này:

```text
Status:       Pod đang Pending/Running/Failed?
Node:         Pod đã được schedule lên node nào chưa?
Containers:   Container đang Waiting/Running/Terminated?
Last State:   Lần chạy trước kết thúc vì lý do gì?
Restart Count: Container đã restart bao nhiêu lần?
Conditions:   PodScheduled, Initialized, Ready, ContainersReady có True không?
Events:       Timeline lỗi từ scheduler, kubelet, image pull, probe, volume
```

Ví dụ chỉ xem phần Events:

```bash
kubectl describe pod nginx-pod -n dev | grep -A 20 "Events:"
```

Cách đọc một số lỗi thường gặp:

| Thấy trong output | Nghĩa là gì | Sửa ở đâu |
|-------------------|-------------|-----------|
| `ErrImagePull` hoặc `ImagePullBackOff` | Kubelet không pull được image | Sửa `spec.containers[].image` hoặc image pull secret |
| `CrashLoopBackOff` | Container start được nhưng process thoát lỗi lặp lại | Xem `logs --previous`, sửa `command`, `args`, env, config hoặc code app |
| `OOMKilled` | Container dùng quá `resources.limits.memory` | Tối ưu app hoặc tăng `resources.limits.memory` |
| `FailedScheduling` | Scheduler không tìm được node phù hợp | Giảm `resources.requests`, sửa nodeSelector/taints/PVC |
| `Readiness probe failed` | App chưa sẵn sàng nhận traffic | Sửa `readinessProbe.path/port/delay` hoặc app endpoint |
| `Liveness probe failed` | Kubernetes coi app đã hỏng và restart container | Sửa `livenessProbe` hoặc nguyên nhân app bị treo |

### Step 6: Debugging với `kubectl logs`

`logs` dùng để đọc output của process trong container. Lệnh này trả lời câu hỏi: "Ứng dụng bên trong container báo lỗi gì?"

```bash
# Xem logs hiện tại của nginx
kubectl logs nginx-pod -n dev

# Xem 20 dòng cuối để đỡ bị ngợp khi log dài
kubectl logs nginx-pod -n dev --tail=20

# Follow logs real-time, hữu ích khi đang gửi request hoặc test probe
kubectl logs nginx-pod -n dev -f --tail=50

# Xem logs trong 30 phút gần nhất
kubectl logs nginx-pod -n dev --since=30m
```

Với pod bị crash, lần chạy hiện tại có thể chưa kịp in lỗi. Khi `RESTARTS > 0`, dùng `--previous`:

```bash
# Pod demo này cố tình exit 1 nên sẽ restart theo restartPolicy=OnFailure
kubectl get pod busybox-onfailure -n dev

# Logs của container đang chạy/lần chạy hiện tại
kubectl logs busybox-onfailure -n dev

# Logs của lần crash trước đó - thường là nơi thấy nguyên nhân thật
kubectl logs busybox-onfailure -n dev --previous
```

Nếu pod có nhiều container, phải chỉ rõ container:

```bash
kubectl logs <pod-name> -c <container-name> -n dev
```

Nếu muốn lấy log của nhiều pod cùng label:

```bash
kubectl logs -l app=nginx -n dev --max-log-requests=10
```

### Step 7: Debugging với `kubectl exec`

`exec` dùng khi container còn `Running` và bạn cần kiểm tra từ bên trong container. Nó không dùng được nếu container đang `Pending`, `ImagePullBackOff`, hoặc crash quá nhanh.

```bash
# Mở interactive shell trong nginx container
kubectl exec -it nginx-pod -n dev -- /bin/sh
```

Trong shell, thử kiểm tra theo thứ tự:

```bash
# 1. File config có tồn tại không?
ls /etc/nginx/
cat /etc/nginx/nginx.conf

# 2. Process chính có đang chạy không?
ps aux

# 3. App có trả lời từ bên trong container không?
wget -qO- http://localhost/

# 4. Env có đúng như YAML khai báo không?
env | sort

# Thoát shell
exit
```

Có thể chạy trực tiếp từng lệnh nếu không cần vào shell:

```bash
kubectl exec nginx-pod -n dev -- ps aux
kubectl exec nginx-pod -n dev -- wget -qO- http://localhost/
kubectl exec nginx-pod -n dev -- env
```

`kubectl cp` chỉ dùng khi thật sự cần lấy file ra để xem hoặc chép file test vào container:

```bash
kubectl cp nginx-pod:/etc/nginx/nginx.conf ./nginx.conf -n dev
kubectl cp ./test-file.txt nginx-pod:/tmp/ -n dev
```

### Step 8: Xem Events trong cluster

Events là timeline các hành động/lỗi mà Kubernetes ghi nhận. Dùng events khi cần nhìn toàn cảnh hoặc khi `describe` của một pod chưa đủ.

```bash
# Xem tất cả events trong namespace
kubectl get events -n dev

# Sort theo thời gian để đọc như timeline
kubectl get events -n dev --sort-by='.lastTimestamp'

# Chỉ xem Warning events để lọc lỗi quan trọng
kubectl get events -n dev --field-selector type=Warning

# Xem events của một pod cụ thể
kubectl get events -n dev --field-selector involvedObject.name=nginx-pod

# Output rộng hơn, có object và source rõ hơn
kubectl get events -n dev -o wide
```

### Step 9: Mini practice - phá lỗi rồi tự sửa

Mục tiêu của bài này là học cách nối triệu chứng với nguyên nhân và cách sửa manifest.

#### Practice A: Sửa lỗi image sai

Tạo một pod cố tình dùng image không tồn tại:

```bash
kubectl run broken-image \
  --image=nginx:not-a-real-tag \
  --restart=Never \
  -n dev

kubectl get pod broken-image -n dev
kubectl describe pod broken-image -n dev | grep -A 20 "Events:"
```

Kết quả mong đợi: pod rơi vào `ErrImagePull` hoặc `ImagePullBackOff`.

Vì sao chạy các lệnh trên:
- `get pod` cho biết triệu chứng bên ngoài.
- `describe ... Events` cho biết kubelet pull image nào và lỗi pull ra sao.

Cách sửa:

```bash
# Cách nhanh trong practice: xóa pod lỗi rồi tạo lại với tag đúng
kubectl delete pod broken-image -n dev
kubectl run broken-image \
  --image=nginx:1.25-alpine \
  --restart=Never \
  -n dev

kubectl get pod broken-image -n dev
```

Nếu lỗi nằm trong YAML, sửa field này:

```yaml
spec:
  containers:
  - name: nginx
    image: nginx:1.25-alpine
```

#### Practice B: Sửa lỗi container crash

Pod `busybox-onfailure` trong `manifests/pod-busybox-restart.yaml` cố tình `exit 1`, nên nó restart liên tục.

```bash
kubectl get pod busybox-onfailure -n dev
kubectl describe pod busybox-onfailure -n dev
kubectl logs busybox-onfailure -n dev --previous
```

Vì sao chạy các lệnh trên:
- `get pod` để thấy `RESTARTS` tăng.
- `describe` để đọc `Last State`, `Exit Code`, `Restart Count`.
- `logs --previous` để đọc log của lần container vừa chết.

Cách sửa trong file `manifests/pod-busybox-restart.yaml`:

```yaml
command:
- sh
- -c
- |
  echo "=== Task Starting ==="
  echo "Current time: $(date)"
  echo "Doing some work..."
  sleep 5
  echo "Task completed successfully! (exit code 0)"
  exit 0
```

Sau khi sửa YAML, apply lại để kiểm tra pod không còn restart:

```bash
kubectl delete pod busybox-onfailure -n dev
kubectl apply -f manifests/pod-busybox-restart.yaml -n dev
kubectl get pods -n dev -w
```

> Lưu ý: `busybox-onfailure` được thiết kế để lỗi nhằm demo `restartPolicy=OnFailure`. Nếu muốn làm lại phần quan sát restart ở Step 10, đổi dòng cuối về `exit 1` rồi apply lại.

### Step 10: Quan sát Restart Policies

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

### Step 11: Port-forward để test pod

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
kubectl delete pod busybox-test --ignore-not-found
kubectl delete pod busybox-shell --ignore-not-found
kubectl delete pod broken-image -n dev --ignore-not-found
kubectl delete pod never-restart -n dev --ignore-not-found
kubectl delete pod fail-never -n dev --ignore-not-found
kubectl delete pod debug-crash -n dev --ignore-not-found

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

# Nếu app crash quá nhanh, tạo pod debug bằng cùng image nhưng override command
# Lưu ý: cách này chỉ giúp khi image pull được; nếu image sai thì phải sửa image trước
kubectl run debug-crash \
  --image=<same-image-as-crashing-pod> \
  --restart=Never \
  -n dev \
  --command -- sleep infinity
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
