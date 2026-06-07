# 🧠 Kubernetes Q&A — Core Concepts

> **Cách dùng:** Đọc câu hỏi, tự trả lời trước, rồi mới mở phần đáp án.
> Mỗi câu có điểm khó: 🟢 Dễ | 🟡 Trung bình | 🔴 Khó

---

## 📦 PHẦN 1 — Pod & Kiến trúc cơ bản

---

**Q1** 🟢 — Pod là gì? Tại sao K8s không chạy container trực tiếp mà phải có Pod?

<details>
<summary>💡 Đáp án</summary>

Pod là đơn vị nhỏ nhất có thể deploy trong Kubernetes. Nó là một wrapper bọc quanh một hoặc nhiều container, đảm bảo chúng:
- Chung **network namespace** (cùng IP, giao tiếp qua localhost)
- Chung **IPC namespace**
- Có thể chia sẻ **volumes**

K8s không chạy container trực tiếp vì Pod cung cấp lớp abstraction cho phép:
- Nhóm các container liên quan lại (sidecar pattern)
- Quản lý lifecycle nhất quán
- Định nghĩa tài nguyên (CPU/Memory) ở cấp nhóm

</details>

---

**Q2** 🟢 — Liệt kê các trạng thái (phase) của một Pod theo thứ tự lifecycle?

<details>
<summary>💡 Đáp án</summary>

```
Pending → Running → Succeeded / Failed
```

- **Pending**: Pod được accepted nhưng chưa có container nào chạy (đang pull image, chờ schedule)
- **Running**: Ít nhất 1 container đang chạy
- **Succeeded**: Tất cả container đã exit 0 (thường dùng với Job)
- **Failed**: Ít nhất 1 container exit non-zero, và sẽ không restart nữa
- **Unknown**: Không lấy được status của Pod (thường do node issue)

</details>

---

**Q3** 🟡 — Sự khác nhau giữa 3 `restartPolicy`: `Always`, `OnFailure`, `Never`? Dùng cái nào trong trường hợp nào?

<details>
<summary>💡 Đáp án</summary>

| Policy | Restart khi nào | Dùng cho |
|--------|----------------|----------|
| `Always` | Luôn restart khi exit (kể cả exit 0) | Deployment, DaemonSet — web server, API |
| `OnFailure` | Chỉ restart khi exit code ≠ 0 | Job — batch job có thể fail cần retry |
| `Never` | Không bao giờ restart | Job một lần, debug pod (`kubectl run -it --rm`) |

> ⚠️ Job và CronJob chỉ chấp nhận `OnFailure` hoặc `Never`, KHÔNG dùng `Always`.

</details>

---

**Q4** 🟡 — Lệnh nào dùng để debug một Pod đang bị lỗi? Liệt kê ít nhất 4 lệnh và giải thích từng lệnh dùng để làm gì.

<details>
<summary>💡 Đáp án</summary>

```bash
# 1. Xem trạng thái tổng quan + Events (quan trọng nhất để debug)
kubectl describe pod <pod-name>

# 2. Xem logs của container (stdout/stderr)
kubectl logs <pod-name>
kubectl logs <pod-name> -c <container-name>  # multi-container pod
kubectl logs <pod-name> --previous           # logs của lần chạy trước (khi pod restart)

# 3. Exec vào trong container để debug trực tiếp
kubectl exec -it <pod-name> -- /bin/sh

# 4. Xem events của namespace
kubectl get events --sort-by='.lastTimestamp' -n <namespace>

# 5. Xem raw YAML để kiểm tra spec
kubectl get pod <pod-name> -o yaml
```

</details>

---

**Q5** 🔴 — Init Container là gì? Nó khác gì container thường? Cho ví dụ thực tế.

<details>
<summary>💡 Đáp án</summary>

**Init Container** chạy TRƯỚC các container chính, theo thứ tự tuần tự.

**Khác biệt:**
| | Init Container | Container thường |
|--|---------------|-----------------|
| Thứ tự chạy | Tuần tự, trước container chính | Song song |
| Exit requirement | Phải exit 0 mới chạy tiếp | Có thể chạy mãi |
| Probe support | Không có liveness/readiness probe | Có |
| Restart khi fail | Toàn bộ Pod restart | Theo restartPolicy |

**Ví dụ thực tế:**
- Chờ database sẵn sàng trước khi app khởi động
- Download config/certificate từ external source
- Clone git repo vào shared volume
- Set permission cho shared volume

```yaml
initContainers:
- name: wait-for-db
  image: busybox
  command: ['sh', '-c', 'until nc -z postgres 5432; do sleep 2; done']
```

</details>

---

**Q6** 🔴 — Tại sao `kubectl run test --image=busybox -it --rm -- wget http://...` bị timeout, còn thêm `--restart=Never` thì lại chạy được?

<details>
<summary>💡 Đáp án</summary>

**Không có `--restart=Never`:**
- Pod được tạo với `restartPolicy: Always`
- Sau khi `wget` hoàn thành → container exit → kubelet **restart ngay lập tức**
- kubectl đang chờ Pod đạt trạng thái `Completed` → **không bao giờ xảy ra** (vì cứ restart mãi)
- Kết quả: kubectl treo, user thấy như "timeout"

**Có `--restart=Never`:**
- Pod dùng `restartPolicy: Never`
- `wget` chạy xong → container exit → Pod chuyển sang `Completed`
- kubectl nhận tín hiệu hoàn thành, `--rm` dọn dẹp Pod
- Kết quả: hoạt động bình thường

> **Rule:** `kubectl run -it --rm` **LUÔN LUÔN phải có `--restart=Never`**

</details>

---

## 🗂️ PHẦN 2 — Namespace & Context

---

**Q7** 🟢 — Namespace là gì? Liệt kê 4 namespace mặc định của K8s và mục đích từng cái.

<details>
<summary>💡 Đáp án</summary>

Namespace là cơ chế phân tách logic trong cluster (như "phòng ban" trong một công ty).

| Namespace | Mục đích |
|-----------|----------|
| `default` | Namespace mặc định khi không chỉ định |
| `kube-system` | Components của K8s control plane (coredns, kube-proxy, metrics-server...) |
| `kube-public` | Resources public, ai cũng đọc được (thường để chứa cluster info) |
| `kube-node-lease` | Lease objects để heartbeat giữa node và control plane |

</details>

---

**Q8** 🟡 — Điều gì KHÔNG được phân tách bởi Namespace? (Cluster-scoped resources)

<details>
<summary>💡 Đáp án</summary>

Các resource **cluster-scoped** (không thuộc namespace nào):
- **Node** — máy chủ vật lý/VM
- **PersistentVolume (PV)** — storage resource (PVC thì có namespace, PV thì không)
- **StorageClass**
- **ClusterRole / ClusterRoleBinding**
- **Namespace** chính nó
- **CustomResourceDefinition (CRD)**

> Kiểm tra bằng: `kubectl api-resources --namespaced=false`

</details>

---

**Q9** 🟡 — Context trong kubeconfig là gì? Nó gồm những thành phần nào?

<details>
<summary>💡 Đáp án</summary>

Context là một "bookmark" kết hợp 3 thông tin:
```
Context = Cluster + User + Namespace (default)
```

Ví dụ:
```yaml
contexts:
- name: prod-ctx
  context:
    cluster: production-cluster
    user: admin
    namespace: production
```

**Lệnh hay dùng:**
```bash
kubectl config get-contexts      # liệt kê tất cả contexts
kubectl config current-context   # context đang dùng
kubectl config use-context <name> # chuyển context
kubectl config set-context --current --namespace=dev  # đổi namespace trong context hiện tại
```

</details>

---

## 🔄 PHẦN 3 — Workloads (Deployment, ReplicaSet, v.v.)

---

**Q10** 🟢 — Sự khác nhau giữa Pod, ReplicaSet, và Deployment? Cái nào quản lý cái nào?

<details>
<summary>💡 Đáp án</summary>

```
Deployment
    └── quản lý ReplicaSet (nhiều revision)
            └── quản lý Pod (nhiều replicas)
```

| Resource | Vai trò |
|----------|---------|
| **Pod** | Đơn vị chạy container |
| **ReplicaSet** | Đảm bảo đúng số lượng Pod đang chạy |
| **Deployment** | Quản lý ReplicaSet, hỗ trợ rolling update và rollback |

**Thực tế:** Bạn gần như không bao giờ tạo ReplicaSet trực tiếp — luôn dùng Deployment.

</details>

---

**Q11** 🟡 — Rolling Update trong Deployment hoạt động như thế nào? `maxSurge` và `maxUnavailable` là gì?

<details>
<summary>💡 Đáp án</summary>

Rolling Update thay thế Pod cũ bằng Pod mới theo từng bước, đảm bảo không có downtime.

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1        # Số Pod có thể tạo THÊM so với desired (vượt quá)
    maxUnavailable: 0  # Số Pod có thể UNAVAILABLE cùng lúc
```

**Ví dụ** với 3 replicas, maxSurge=1, maxUnavailable=0:
1. Tạo Pod mới (v2) → tổng 4 pods
2. Khi Pod v2 Ready → xóa 1 Pod v1 → tổng 3 pods
3. Lặp lại đến khi tất cả là v2

**Lệnh theo dõi:**
```bash
kubectl rollout status deployment/<name>
kubectl rollout history deployment/<name>
kubectl rollout undo deployment/<name>      # rollback
kubectl rollout undo deployment/<name> --to-revision=2  # rollback về revision cụ thể
```

</details>

---

**Q12** 🟡 — Khi nào dùng DaemonSet thay vì Deployment?

<details>
<summary>💡 Đáp án</summary>

**DaemonSet** đảm bảo **mỗi Node chạy đúng 1 Pod** (hoặc trên các Node được chọn).

Dùng DaemonSet khi cần:
- **Log collector**: Fluentd, Filebeat — thu thập log từ mỗi node
- **Monitoring agent**: Prometheus Node Exporter — metrics từng node
- **Network plugin**: Calico, Flannel — CNI plugin
- **Storage daemon**: Ceph, GlusterFS daemon

**Khác Deployment:**
- Deployment: bạn chỉ định số replica (3 pods trên bất kỳ node nào)
- DaemonSet: 1 pod/node, tự thêm khi có node mới, tự xóa khi node bị remove

</details>

---

**Q13** 🔴 — StatefulSet khác Deployment ở những điểm nào? Khi nào bắt buộc phải dùng StatefulSet?

<details>
<summary>💡 Đáp án</summary>

| | Deployment | StatefulSet |
|--|-----------|------------|
| **Pod name** | Random (nginx-7d9f8-xkz2p) | Có thứ tự (nginx-0, nginx-1) |
| **DNS** | Chỉ qua Service | Mỗi Pod có DNS riêng (nginx-0.svc) |
| **Storage** | Chia sẻ hoặc không persistent | Mỗi Pod có PVC riêng (`volumeClaimTemplates`) |
| **Thứ tự** | Tạo/xóa song song | Tạo: 0→1→2, Xóa: 2→1→0 |

**Bắt buộc dùng StatefulSet khi:**
- Database cluster: MySQL Primary/Replica, MongoDB ReplicaSet
- Message queue: Kafka, RabbitMQ cluster
- Distributed storage: Elasticsearch, Cassandra
- Bất kỳ app nào cần **stable network identity** hoặc **stable persistent storage**

</details>

---

**Q14** 🟡 — Job và CronJob khác nhau thế nào? Các tham số `completions`, `parallelism`, `backoffLimit` dùng để làm gì?

<details>
<summary>💡 Đáp án</summary>

- **Job**: Chạy task đến khi hoàn thành (exit 0)
- **CronJob**: Tạo Job theo lịch (dùng cron expression)

**Tham số Job:**

| Tham số | Ý nghĩa |
|---------|---------|
| `completions: 5` | Tổng số lần cần chạy thành công |
| `parallelism: 2` | Số Pod chạy đồng thời |
| `backoffLimit: 4` | Số lần retry tối đa trước khi Job fail |
| `activeDeadlineSeconds: 300` | Timeout toàn bộ Job (giây) |

**Tham số CronJob thêm:**

| Tham số | Ý nghĩa |
|---------|---------|
| `concurrencyPolicy: Forbid` | Không chạy job mới nếu job trước chưa xong |
| `successfulJobsHistoryLimit: 3` | Giữ lại bao nhiêu job history |

</details>

---

## 🌐 PHẦN 4 — Networking & Service

---

**Q15** 🟢 — Liệt kê 4 loại Service trong K8s. Mỗi loại dùng trong tình huống nào?

<details>
<summary>💡 Đáp án</summary>

| Type | Expose ra đâu | Dùng khi |
|------|--------------|---------|
| **ClusterIP** (default) | Chỉ trong cluster | Giao tiếp giữa các service nội bộ |
| **NodePort** | Expose qua IP của Node + port (30000-32767) | Dev/test, khi không có LB |
| **LoadBalancer** | Tạo cloud LB, có external IP | Production trên cloud (AWS/GCP/Azure) |
| **ExternalName** | CNAME đến external DNS | Trỏ đến external database/API |

> **Quan hệ kế thừa:** LoadBalancer ⊃ NodePort ⊃ ClusterIP

</details>

---

**Q16** 🟡 — DNS trong K8s hoạt động thế nào? Format DNS đầy đủ của một Service là gì?

<details>
<summary>💡 Đáp án</summary>

K8s dùng **CoreDNS** để resolve tên service thành IP.

**Format DNS đầy đủ:**
```
<service-name>.<namespace>.svc.cluster.local
```

**Ví dụ:**
```bash
# Service "postgres" trong namespace "prod"
postgres.prod.svc.cluster.local

# Từ cùng namespace, có thể dùng tên ngắn:
postgres               # hoặc
postgres.prod          # hoặc
postgres.prod.svc
```

**Tại sao quan trọng:** Không bao giờ hardcode IP — dùng DNS name thay thế, vì IP của Service không đổi nhưng IP của Pod thay đổi liên tục.

</details>

---

**Q17** 🟡 — Ingress là gì? Tại sao cần Ingress khi đã có Service?

<details>
<summary>💡 Đáp án</summary>

**Ingress** là resource quản lý HTTP/HTTPS routing từ bên ngoài vào các Service trong cluster.

**Vấn đề nếu chỉ dùng Service:**
- LoadBalancer: mỗi Service cần 1 LB riêng → tốn tiền, khó quản lý
- NodePort: không professional, expose port ngẫu nhiên

**Ingress giải quyết:** Một điểm vào duy nhất, route dựa trên:

```
                    Ingress Controller
                          │
         ┌────────────────┼────────────────┐
         ▼                ▼                ▼
   /api → api-svc   /web → web-svc   app2.com → svc-2
```

- **Path-based routing**: `myapp.com/api` → api-service, `myapp.com/` → frontend-service
- **Host-based routing**: `api.myapp.com` → api-service, `admin.myapp.com` → admin-service
- **TLS termination**: HTTPS tại Ingress, HTTP trong cluster

> **Cần nhớ:** Ingress **resource** chỉ là config. Cần **Ingress Controller** (nginx, traefik...) để thực thi.

</details>

---

**Q18** 🔴 — NetworkPolicy mặc định của K8s là gì? Làm sao để implement "default deny all"?

<details>
<summary>💡 Đáp án</summary>

**Mặc định của K8s:** Tất cả Pod có thể giao tiếp với nhau (allow all) — không có firewall.

**Default deny all ingress:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}        # {} = áp dụng cho TẤT CẢ pods trong namespace
  policyTypes:
  - Ingress
  - Egress
  # Không có rules → block tất cả
```

**Sau đó mở từng port cần thiết:**
```yaml
# Cho phép frontend gọi backend:80
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - port: 80
```

> ⚠️ NetworkPolicy chỉ hoạt động nếu CNI plugin hỗ trợ (Calico, Cilium, Weave). Flannel không hỗ trợ.

</details>

---

## ⚙️ PHẦN 5 — Configuration & Storage

---

**Q19** 🟢 — ConfigMap là gì? Có bao nhiêu cách inject ConfigMap vào Pod?

<details>
<summary>💡 Đáp án</summary>

**ConfigMap** lưu trữ config data dạng key-value, tách biệt config ra khỏi image container.

**3 cách inject vào Pod:**

**1. Environment variable (từng key):**
```yaml
env:
- name: APP_PORT
  valueFrom:
    configMapKeyRef:
      name: my-config
      key: port
```

**2. Environment variable (tất cả keys):**
```yaml
envFrom:
- configMapRef:
    name: my-config
```

**3. Volume mount (mỗi key = một file):**
```yaml
volumes:
- name: config-vol
  configMap:
    name: my-config
volumeMounts:
- name: config-vol
  mountPath: /etc/config
```

> **Khi nào dùng volume:** Khi config là file (nginx.conf, app.properties...) và app cần reload khi config thay đổi.

</details>

---

**Q20** 🟡 — Secret khác ConfigMap ở điểm nào? Secret có thực sự "bí mật" không?

<details>
<summary>💡 Đáp án</summary>

**Khác biệt kỹ thuật:**

| | ConfigMap | Secret |
|--|-----------|--------|
| Encoding | Plain text | Base64 |
| Lưu trong etcd | Plain text | Base64 (chưa encrypt mặc định) |
| Hiển thị khi `kubectl get` | Thấy trực tiếp | Base64 encoded |
| `kubectl describe` | Thấy values | **KHÔNG** thấy values |

**Secret có thực sự bí mật không?**
**❌ Không hoàn toàn!** Base64 là encode, **không phải encrypt**. Ai có quyền đọc Secret đều decode được:
```bash
kubectl get secret my-secret -o jsonpath='{.data.password}' | base64 -d
# → plain text password
```

**Để thực sự bảo mật cần:**
- Encryption at rest (cấu hình thêm cho etcd)
- Sealed Secrets (Bitnami)
- External Secrets Operator (tích hợp Vault/AWS)

</details>

---

**Q21** 🟡 — PersistentVolume (PV), PersistentVolumeClaim (PVC), và StorageClass liên quan với nhau thế nào?

<details>
<summary>💡 Đáp án</summary>

```
StorageClass        PersistentVolume (PV)     PersistentVolumeClaim (PVC)
     │                      │                           │
  "Loại ổ đĩa"          "Ổ đĩa thực"              "Yêu cầu ổ đĩa"
  (fast-ssd, slow-hdd)   (quản lý bởi admin)       (do developer tạo)
     │                      │                           │
     └──── Dynamic: PV tự động tạo khi có PVC ─────────┘
           Static: Admin tạo PV trước, PVC bind vào
```

**Luồng hoạt động:**
1. Admin tạo StorageClass (hoặc dùng default)
2. Developer tạo PVC với `storageClassName` và dung lượng cần
3. K8s tự tạo PV (dynamic provisioning) và **bind** PVC với PV
4. Pod mount PVC như một volume

**Access Modes:**
- `ReadWriteOnce (RWO)`: 1 node đọc/ghi (phổ biến nhất)
- `ReadOnlyMany (ROX)`: nhiều node chỉ đọc
- `ReadWriteMany (RWX)`: nhiều node đọc/ghi (cần NFS/Ceph)

</details>

---

**Q22** 🟡 — `requests` và `limits` trong resource management là gì? Chúng ảnh hưởng đến scheduling như thế nào?

<details>
<summary>💡 Đáp án</summary>

```yaml
resources:
  requests:
    cpu: "100m"      # 0.1 core — scheduler dùng để chọn node
    memory: "128Mi"  # Đảm bảo Node có ít nhất 128Mi trống
  limits:
    cpu: "500m"      # 0.5 core — cap cứng, không thể vượt quá
    memory: "256Mi"  # Nếu vượt quá → OOMKilled
```

**Scheduler dùng `requests` để quyết định node:**
- Node phải có đủ **allocatable** resources ≥ requests của Pod
- Scheduler KHÔNG dùng limits để quyết định

**Điều xảy ra khi vượt limit:**
- CPU: bị throttle (chạy chậm lại, không bị kill)
- Memory: container bị **OOMKilled** (restart)

**QoS Classes:**
- `Guaranteed`: requests = limits → ưu tiên cao nhất
- `Burstable`: requests < limits → thường dùng
- `BestEffort`: không set requests/limits → bị kill đầu tiên khi node thiếu tài nguyên

</details>

---

## 🔁 PHẦN 6 — Câu hỏi tình huống thực tế

---

**Q23** 🟡 — **Tình huống:** Pod của bạn ở trạng thái `CrashLoopBackOff`. Bạn sẽ debug theo thứ tự nào?

<details>
<summary>💡 Đáp án</summary>

```bash
# Bước 1: Xem logs của container (lý do crash thường ở đây)
kubectl logs <pod-name>
kubectl logs <pod-name> --previous   # logs của lần crash trước

# Bước 2: Xem describe để xem Events và last state
kubectl describe pod <pod-name>
# Chú ý: Last State, Exit Code, Reason

# Bước 3: Kiểm tra exit code
# Exit code 1: application error (check app logs)
# Exit code 137: OOMKilled (tăng memory limits)
# Exit code 143: SIGTERM không được handle (graceful shutdown issue)

# Bước 4: Nếu container không start được, exec vào bằng cách override command
kubectl run debug --image=<same-image> --restart=Never -it --rm -- /bin/sh

# Bước 5: Kiểm tra ConfigMap/Secret có đúng không
kubectl describe configmap <name>
kubectl get secret <name> -o yaml
```

**Nguyên nhân CrashLoopBackOff thường gặp:**
- App code bị lỗi khi start
- Thiếu environment variable / config
- OOMKilled (thiếu memory)
- Liveness probe quá aggressive
- Init container fail

</details>

---

**Q24** 🟡 — **Tình huống:** Bạn có Service nhưng không thể kết nối tới Pod. Debug thế nào?

<details>
<summary>💡 Đáp án</summary>

```bash
# Bước 1: Kiểm tra Service có Endpoints không
kubectl get endpoints <service-name>
# Nếu "Endpoints: <none>" → Label Selector sai

# Bước 2: Kiểm tra label selector của Service khớp với label của Pod
kubectl describe svc <service-name>  # xem Selector
kubectl get pods --show-labels       # xem labels của pods

# Bước 3: Kiểm tra Pod có READY không
kubectl get pods  # cột READY phải là 1/1

# Bước 4: Test connectivity từ trong cluster
kubectl run test --image=busybox:1.36 --restart=Never -it --rm \
  -- wget -qO- http://<service-name>.<namespace>.svc.cluster.local

# Bước 5: Kiểm tra port mapping
kubectl describe svc <service-name>
# Port (Service port) vs TargetPort (Container port) phải đúng

# Bước 6: Kiểm tra NetworkPolicy có block không
kubectl get networkpolicy -n <namespace>
```

</details>

---

**Q25** 🔴 — **Tình huống:** Deployment có 3 replicas nhưng chỉ có 2 Pod đang chạy, 1 Pod ở trạng thái `Pending`. Nguyên nhân có thể là gì?

<details>
<summary>💡 Đáp án</summary>

```bash
# Xem lý do Pending
kubectl describe pod <pending-pod-name>
# Chú ý phần "Events:" ở cuối output
```

**Nguyên nhân thường gặp khi Pod `Pending`:**

| Nguyên nhân | Triệu chứng trong Events |
|-------------|--------------------------|
| **Không đủ CPU/Memory** | `Insufficient cpu` hoặc `Insufficient memory` |
| **Không có Node phù hợp** | `0/3 nodes are available` |
| **PVC chưa được bind** | `persistentvolumeclaim not found` |
| **Image pull đang chờ** | `ContainerCreating` → đang pull |
| **Taint không có Toleration** | `node(s) had untolerated taint` |
| **NodeSelector không match** | `node(s) didn't match node selector` |
| **ResourceQuota vượt limit** | `exceeded quota` |

**Kiểm tra nhanh:**
```bash
kubectl describe node | grep -A5 "Allocated resources"
kubectl get events --field-selector reason=FailedScheduling
```

</details>

---

**Q26** 🔴 — **Tình huống:** Bạn cần deploy app mới nhưng muốn không có downtime. Deployment strategy nào phù hợp và cấu hình thế nào?

<details>
<summary>💡 Đáp án</summary>

**Dùng Rolling Update strategy (default):**

```yaml
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0    # Không cho phép Pod nào unavailable
      maxSurge: 1          # Tạo thêm tối đa 1 Pod mới khi update
```

**Đảm bảo zero-downtime cần thêm:**

1. **Readiness Probe** — chỉ route traffic khi Pod thực sự ready:
```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5
```

2. **preStop hook** — hoàn thành request đang xử lý trước khi tắt:
```yaml
lifecycle:
  preStop:
    exec:
      command: ["/bin/sh", "-c", "sleep 5"]
terminationGracePeriodSeconds: 30
```

3. **PodDisruptionBudget** — bảo vệ khi maintenance:
```yaml
spec:
  minAvailable: 2   # Luôn ít nhất 2 pod running
```

**Verify:**
```bash
kubectl rollout status deployment/<name>  # theo dõi tiến trình
```

</details>

---

## 🎯 Bảng tự chấm điểm

| Phần | Câu | Trả lời đúng |
|------|-----|-------------|
| Pod & Kiến trúc | Q1–Q6 | /6 |
| Namespace & Context | Q7–Q9 | /3 |
| Workloads | Q10–Q14 | /5 |
| Networking | Q15–Q18 | /4 |
| Configuration & Storage | Q19–Q22 | /4 |
| Tình huống thực tế | Q23–Q26 | /4 |
| **TỔNG** | | **/26** |

### Đánh giá

| Điểm | Mức độ |
|------|--------|
| 22–26 | 🏆 Excellent — Sẵn sàng sang Phase Advanced |
| 17–21 | ✅ Good — Nắm vững cốt lõi, cần ôn một số phần |
| 12–16 | 📖 Fair — Cần xem lại lab và thực hành thêm |
| < 12 | 🔄 Needs work — Quay lại từ Lab 01, đừng vội |

---

> 💡 **Tip học hiệu quả:** Sau khi đọc đáp án, hãy tự tay chạy lệnh/apply YAML để kiểm chứng — đừng chỉ đọc lý thuyết!
