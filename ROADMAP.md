# 🚀 Kubernetes Practice Roadmap — From Zero to Hero

> **Mục tiêu:** Thực hành Kubernetes từ cơ bản đến nâng cao thông qua các lab có cấu trúc rõ ràng.
> Mỗi lab tương ứng với **một commit có ý nghĩa** trên GitHub.

---

## 📌 Quy ước Git Commit

Mỗi lab hoàn thành → commit theo format:

```
lab(XX): <tên lab ngắn gọn>

- Đã làm gì
- Output đạt được
```

Ví dụ:
```
lab(01): deploy first pod

- Tạo Pod nginx bằng kubectl run và YAML manifest
- Kiểm tra trạng thái Pod với kubectl get/describe
```

---

## 🗺️ Lộ Trình Tổng Quan

| Giai đoạn | Chủ đề | Số Lab |
|-----------|--------|--------|
| 🟢 **Phase 1** | Nền tảng & Kiến trúc K8s | Lab 01 – 04 |
| 🔵 **Phase 2** | Workloads cơ bản | Lab 05 – 09 |
| 🟡 **Phase 3** | Networking & Service | Lab 10 – 14 |
| 🟠 **Phase 4** | Storage & Configuration | Lab 15 – 19 |
| 🔴 **Phase 5** | Advanced Workloads | Lab 20 – 24 |
| 🟣 **Phase 6** | Security & RBAC | Lab 25 – 28 |
| ⚫ **Phase 7** | Observability | Lab 29 – 32 |
| 🌟 **Phase 8** | Production Patterns | Lab 33 – 36 |

---

## 🟢 Phase 1 — Nền Tảng & Kiến Trúc K8s

### Lab 01 — Khởi động với kubectl & Cluster Info
**Thư mục:** `lab-01-kubectl-basics/`
**Commit:** `lab(01): explore cluster with kubectl basics`

**Bạn sẽ học được:**
- Cách cài đặt và cấu hình `kubectl`
- Kiến trúc cluster K8s (control plane, worker nodes)
- Các lệnh `kubectl` cơ bản: `get`, `describe`, `explain`, `api-resources`
- Đọc và hiểu `kubeconfig`

**Nội dung thực hành:**
```bash
kubectl cluster-info
kubectl get nodes -o wide
kubectl get namespaces
kubectl explain pod
kubectl api-resources
```

**Output đạt được:** ✅ Hiểu cấu trúc cluster, biết dùng kubectl để khám phá tài nguyên K8s.

---

### Lab 02 — Namespace & Context
**Thư mục:** `lab-02-namespace-context/`
**Commit:** `lab(02): manage namespaces and kubectl contexts`

**Bạn sẽ học được:**
- Namespace là gì và tại sao cần dùng
- Tạo và quản lý Namespace
- Chuyển đổi context với `kubectl config`
- Phân tách tài nguyên theo môi trường (dev/staging/prod)

**Nội dung thực hành:**
```bash
kubectl create namespace dev
kubectl create namespace staging
kubectl config set-context --current --namespace=dev
kubectl get all -n staging
```

**Output đạt được:** ✅ Biết cách tổ chức tài nguyên theo namespace, chuyển đổi context linh hoạt.

---

### Lab 03 — Pod Lifecycle & Manifest cơ bản
**Thư mục:** `lab-03-pod-lifecycle/`
**Commit:** `lab(03): understand pod lifecycle and write YAML manifests`

**Bạn sẽ học được:**
- Vòng đời của một Pod (Pending → Running → Succeeded/Failed)
- Viết Pod manifest YAML từ đầu
- Các lệnh debug: `kubectl logs`, `kubectl exec`, `kubectl describe`
- Restart policies

**Nội dung thực hành:**
```yaml
# pod-nginx.yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod
  namespace: dev
spec:
  containers:
  - name: nginx
    image: nginx:1.25
    ports:
    - containerPort: 80
  restartPolicy: Always
```

**Output đạt được:** ✅ Tự tay viết YAML, deploy Pod và debug khi Pod không khởi động được.

---

### Lab 04 — Multi-container Pod & Init Container
**Thư mục:** `lab-04-multicontainer-pod/`
**Commit:** `lab(04): implement sidecar and init container patterns`

**Bạn sẽ học được:**
- Patterns: Sidecar, Ambassador, Adapter
- Init Container là gì và khi nào dùng
- Chia sẻ dữ liệu giữa các container trong cùng Pod (`emptyDir`)
- Thứ tự khởi động container

**Output đạt được:** ✅ Hiểu design pattern multi-container, biết dùng init container để pre-setup môi trường.

---

## 🔵 Phase 2 — Workloads Cơ Bản

### Lab 05 — ReplicaSet & Self-healing
**Thư mục:** `lab-05-replicaset/`
**Commit:** `lab(05): deploy replicaset and observe self-healing`

**Bạn sẽ học được:**
- ReplicaSet đảm bảo số lượng Pod mong muốn
- Label Selector hoạt động như thế nào
- Self-healing: xóa Pod và quan sát K8s tự tạo lại
- Scale thủ công

**Output đạt được:** ✅ Chứng kiến tính self-healing của K8s, hiểu vai trò của Labels & Selectors.

---

### Lab 06 — Deployment & Rolling Update
**Thư mục:** `lab-06-deployment/`
**Commit:** `lab(06): manage deployments with rolling update and rollback`

**Bạn sẽ học được:**
- Deployment quản lý ReplicaSet như thế nào
- Rolling Update strategy (maxSurge, maxUnavailable)
- Rollback về version trước với `kubectl rollout undo`
- Xem lịch sử rollout

**Nội dung thực hành:**
```bash
kubectl set image deployment/nginx-deploy nginx=nginx:1.26
kubectl rollout status deployment/nginx-deploy
kubectl rollout history deployment/nginx-deploy
kubectl rollout undo deployment/nginx-deploy
```

**Output đạt được:** ✅ Deploy và cập nhật ứng dụng không downtime, rollback khi có lỗi.

---

### Lab 07 — DaemonSet & Static Pod
**Thư mục:** `lab-07-daemonset/`
**Commit:** `lab(07): deploy daemonset for node-level workloads`

**Bạn sẽ học được:**
- DaemonSet chạy Pod trên mỗi Node (log collector, monitoring agent)
- Cách DaemonSet phản ứng khi thêm/xóa Node
- Static Pod là gì (dùng trong control plane)
- Node Selector với DaemonSet

**Output đạt được:** ✅ Biết triển khai agent cấp Node như Fluentd, Prometheus Node Exporter.

---

### Lab 08 — StatefulSet & Headless Service
**Thư mục:** `lab-08-statefulset/`
**Commit:** `lab(08): deploy stateful application with statefulset`

**Bạn sẽ học được:**
- Sự khác biệt StatefulSet vs Deployment
- Pod identity ổn định (pod-0, pod-1, ...)
- Headless Service để kết nối trực tiếp tới Pod
- Ordered deployment và termination

**Output đạt được:** ✅ Deploy ứng dụng có state (ví dụ: MySQL, Redis cluster) đúng cách.

---

### Lab 09 — Job & CronJob
**Thư mục:** `lab-09-job-cronjob/`
**Commit:** `lab(09): run batch workloads with job and cronjob`

**Bạn sẽ học được:**
- Job chạy tác vụ một lần đến completion
- CronJob lên lịch chạy định kỳ
- Parallel Jobs (completions, parallelism)
- Xử lý Job thất bại (backoffLimit)

**Output đạt được:** ✅ Biết xử lý batch processing và scheduled tasks trong K8s.

---

## 🟡 Phase 3 — Networking & Service

### Lab 10 — Service Types (ClusterIP, NodePort, LoadBalancer)
**Thư mục:** `lab-10-service-types/`
**Commit:** `lab(10): expose applications with different service types`

**Bạn sẽ học được:**
- ClusterIP: giao tiếp nội bộ cluster
- NodePort: expose ra ngoài qua port của Node
- LoadBalancer: tích hợp với cloud load balancer
- ExternalName: ánh xạ tới external DNS

**Output đạt được:** ✅ Hiểu và áp dụng đúng loại Service cho từng use case.

---

### Lab 11 — DNS & Service Discovery
**Thư mục:** `lab-11-dns-discovery/`
**Commit:** `lab(11): configure service discovery with CoreDNS`

**Bạn sẽ học được:**
- CoreDNS trong K8s hoạt động ra sao
- Format DNS: `<service>.<namespace>.svc.cluster.local`
- Service discovery giữa các namespace
- Debug DNS với `nslookup`, `dig` trong Pod

**Output đạt được:** ✅ Kết nối service với service dùng DNS thay vì hardcode IP.

---

### Lab 12 — Ingress & Ingress Controller
**Thư mục:** `lab-12-ingress/`
**Commit:** `lab(12): route external traffic with nginx ingress controller`

**Bạn sẽ học được:**
- Ingress là gì và tại sao cần (so với NodePort/LoadBalancer)
- Cài đặt NGINX Ingress Controller
- Path-based routing và host-based routing
- TLS termination với Ingress

**Nội dung thực hành:**
```yaml
# ingress.yaml
rules:
- host: app.local
  http:
    paths:
    - path: /api
      backend:
        service:
          name: api-svc
          port:
            number: 8080
    - path: /
      backend:
        service:
          name: frontend-svc
          port:
            number: 80
```

**Output đạt được:** ✅ Expose nhiều service qua một điểm vào duy nhất với domain-based routing.

---

### Lab 13 — NetworkPolicy
**Thư mục:** `lab-13-network-policy/`
**Commit:** `lab(13): secure pod communication with network policies`

**Bạn sẽ học được:**
- Mặc định K8s cho phép tất cả traffic
- NetworkPolicy để kiểm soát ingress/egress
- Deny-all policy và chỉ cho phép traffic cụ thể
- Debug NetworkPolicy với `kubectl exec` + `curl`

**Output đạt được:** ✅ Implement network segmentation, bảo vệ các service nhạy cảm.

---

### Lab 14 — EndpointSlice & External Services
**Thư mục:** `lab-14-endpoints/`
**Commit:** `lab(14): connect k8s services to external resources`

**Bạn sẽ học được:**
- Endpoint và EndpointSlice là gì
- Tạo Service không có Selector để kết nối external DB
- ExternalName Service
- Headless Service với custom endpoints

**Output đạt được:** ✅ Kết nối ứng dụng K8s với tài nguyên bên ngoài cluster.

---

## 🟠 Phase 4 — Storage & Configuration

### Lab 15 — ConfigMap
**Thư mục:** `lab-15-configmap/`
**Commit:** `lab(15): externalize configuration with configmaps`

**Bạn sẽ học được:**
- Tạo ConfigMap từ literal, file, directory
- Inject vào Pod dạng env var và volume mount
- Update ConfigMap và reload ứng dụng
- Best practices quản lý config

**Output đạt được:** ✅ Tách config ra khỏi image, dễ dàng thay đổi config không cần build lại.

---

### Lab 16 — Secret
**Thư mục:** `lab-16-secret/`
**Commit:** `lab(16): manage sensitive data with kubernetes secrets`

**Bạn sẽ học được:**
- Các loại Secret (Opaque, TLS, dockerconfigjson)
- Encode/decode base64
- Inject Secret vào Pod (env var vs volume)
- Hạn chế của Secret (không encrypt mặc định)
- Giới thiệu Sealed Secrets / External Secrets

**Output đạt được:** ✅ Quản lý credentials và sensitive data đúng cách trong K8s.

---

### Lab 17 — PersistentVolume & PersistentVolumeClaim
**Thư mục:** `lab-17-persistent-volume/`
**Commit:** `lab(17): persist data with PV and PVC`

**Bạn sẽ học được:**
- PV, PVC, StorageClass là gì
- Static vs Dynamic provisioning
- Access Modes: ReadWriteOnce, ReadOnlyMany, ReadWriteMany
- Reclaim Policies: Retain, Delete, Recycle
- Mount PVC vào Pod

**Output đạt được:** ✅ Lưu trữ dữ liệu bền vững cho stateful applications.

---

### Lab 18 — StorageClass & Dynamic Provisioning
**Thư mục:** `lab-18-storageclass/`
**Commit:** `lab(18): automate storage with dynamic provisioning`

**Bạn sẽ học được:**
- StorageClass parameters và provisioner
- Tạo custom StorageClass
- Volume expansion
- Volume Snapshot (nếu CSI driver hỗ trợ)

**Output đạt được:** ✅ Tự động hóa việc cấp phát storage, không cần tạo PV thủ công.

---

### Lab 19 — Resource Requests & Limits
**Thư mục:** `lab-19-resource-management/`
**Commit:** `lab(19): control resource consumption with requests and limits`

**Bạn sẽ học được:**
- CPU và Memory requests/limits
- QoS Classes: Guaranteed, Burstable, BestEffort
- LimitRange và ResourceQuota cho Namespace
- Quan sát resource usage với `kubectl top`

**Output đạt được:** ✅ Kiểm soát tài nguyên, tránh một Pod chiếm hết tài nguyên cluster.

---

## 🔴 Phase 5 — Advanced Workloads

### Lab 20 — Horizontal Pod Autoscaler (HPA)
**Thư mục:** `lab-20-hpa/`
**Commit:** `lab(20): auto-scale pods based on CPU metrics with HPA`

**Bạn sẽ học được:**
- HPA tự động scale Deployment theo CPU/Memory
- Cài đặt Metrics Server
- Tạo HPA và stress test
- Custom metrics với KEDA (giới thiệu)

**Output đạt được:** ✅ Ứng dụng tự scale up khi tải cao, scale down khi tải thấp.

---

### Lab 21 — Vertical Pod Autoscaler (VPA)
**Thư mục:** `lab-21-vpa/`
**Commit:** `lab(21): optimize resource allocation with VPA`

**Bạn sẽ học được:**
- VPA tự động điều chỉnh requests/limits
- Modes: Off, Initial, Auto
- So sánh HPA vs VPA
- Khi nào dùng HPA, khi nào dùng VPA

**Output đạt được:** ✅ Tự động tối ưu tài nguyên cho Pod dựa trên lịch sử sử dụng.

---

### Lab 22 — Taints, Tolerations & Node Affinity
**Thư mục:** `lab-22-scheduling/`
**Commit:** `lab(22): control pod scheduling with taints tolerations and affinity`

**Bạn sẽ học được:**
- Taint Node để "đuổi" Pod ra
- Toleration cho phép Pod chịu đựng Taint
- NodeSelector vs NodeAffinity (required/preferred)
- Pod Affinity/Anti-Affinity

**Output đạt được:** ✅ Điều phối Pod chạy đúng Node mong muốn, phân tán Pod tránh single point of failure.

---

### Lab 23 — Pod Disruption Budget (PDB)
**Thư mục:** `lab-23-pdb/`
**Commit:** `lab(23): ensure high availability with pod disruption budgets`

**Bạn sẽ học được:**
- PDB bảo vệ số lượng Pod tối thiểu khi maintenance
- minAvailable vs maxUnavailable
- Thử nghiệm với `kubectl drain`
- Kết hợp PDB với rolling update strategy

**Output đạt được:** ✅ Đảm bảo ứng dụng không bị gián đoạn khi upgrade Node hoặc maintenance.

---

### Lab 24 — Custom Resource Definition (CRD) & Operator Pattern
**Thư mục:** `lab-24-crd-operator/`
**Commit:** `lab(24): extend kubernetes API with CRD and operators`

**Bạn sẽ học được:**
- CRD là gì và tại sao cần mở rộng API K8s
- Tạo CRD đơn giản
- Operator Pattern: controller reconcile loop
- Giới thiệu Operator SDK / Kubebuilder
- Ví dụ thực tế: cert-manager, prometheus-operator

**Output đạt được:** ✅ Hiểu cách K8s được mở rộng, biết sử dụng và tạo Custom Resource.

---

## 🟣 Phase 6 — Security & RBAC

### Lab 25 — RBAC: Role & ClusterRole
**Thư mục:** `lab-25-rbac/`
**Commit:** `lab(25): implement RBAC for fine-grained access control`

**Bạn sẽ học được:**
- Authentication vs Authorization trong K8s
- Role, ClusterRole, RoleBinding, ClusterRoleBinding
- ServiceAccount và cách Pod dùng SA
- Kiểm tra quyền với `kubectl auth can-i`

**Output đạt được:** ✅ Implement least-privilege access, phân quyền rõ ràng giữa các team.

---

### Lab 26 — Security Context & Pod Security Standards
**Thư mục:** `lab-26-pod-security/`
**Commit:** `lab(26): harden pod security with security context and PSS`

**Bạn sẽ học được:**
- SecurityContext: runAsUser, runAsNonRoot, readOnlyRootFilesystem
- Capabilities: drop và add
- Pod Security Standards (Privileged/Baseline/Restricted)
- Pod Security Admission Controller

**Output đạt được:** ✅ Chạy container theo nguyên tắc least privilege, giảm attack surface.

---

### Lab 27 — Network Policy nâng cao & Zero-trust
**Thư mục:** `lab-27-zero-trust-network/`
**Commit:** `lab(27): implement zero-trust networking with strict network policies`

**Bạn sẽ học được:**
- Default deny all ingress/egress
- Cho phép traffic từng bước một
- Kiểm tra policy với các tool như `netpol-viz`
- Giới thiệu service mesh (Istio/Linkerd) cho mTLS

**Output đạt được:** ✅ Xây dựng mô hình zero-trust network trong K8s cluster.

---

### Lab 28 — Secret Management với External Secrets
**Thư mục:** `lab-28-external-secrets/`
**Commit:** `lab(28): integrate external secret stores with k8s`

**Bạn sẽ học được:**
- Vấn đề của K8s Secret mặc định (base64, không encrypted)
- External Secrets Operator
- Tích hợp với Vault / AWS Secrets Manager / GCP Secret Manager
- Sealed Secrets cho GitOps

**Output đạt được:** ✅ Quản lý secret an toàn, phù hợp với môi trường production.

---

## ⚫ Phase 7 — Observability

### Lab 29 — Logging với EFK Stack
**Thư mục:** `lab-29-logging-efk/`
**Commit:** `lab(29): centralize logs with elasticsearch fluentd kibana`

**Bạn sẽ học được:**
- Log aggregation architecture trong K8s
- Deploy Elasticsearch, Fluentd (DaemonSet), Kibana
- Tạo structured log từ ứng dụng
- Query và visualize logs trên Kibana

**Output đạt được:** ✅ Thu thập và tìm kiếm logs tập trung từ toàn bộ cluster.

---

### Lab 30 — Metrics với Prometheus & Grafana
**Thư mục:** `lab-30-prometheus-grafana/`
**Commit:** `lab(30): monitor cluster metrics with prometheus and grafana`

**Bạn sẽ học được:**
- Deploy Prometheus với kube-prometheus-stack (Helm)
- ServiceMonitor và PodMonitor
- Tạo custom metrics từ ứng dụng
- Xây dựng dashboard Grafana
- AlertManager: cấu hình alert rules

**Output đạt được:** ✅ Dashboard monitoring đầy đủ, cảnh báo khi có sự cố.

---

### Lab 31 — Distributed Tracing với Jaeger
**Thư mục:** `lab-31-tracing-jaeger/`
**Commit:** `lab(31): implement distributed tracing with opentelemetry and jaeger`

**Bạn sẽ học được:**
- Distributed tracing là gì và tại sao cần
- OpenTelemetry SDK
- Deploy Jaeger
- Trace request qua nhiều service
- Phân tích bottleneck

**Output đạt được:** ✅ Theo dõi request xuyên suốt microservices, phát hiện performance bottleneck.

---

### Lab 32 — Health Checks: Liveness, Readiness, Startup Probe
**Thư mục:** `lab-32-probes/`
**Commit:** `lab(32): implement health checks with k8s probes`

**Bạn sẽ học được:**
- Liveness Probe: restart container khi unhealthy
- Readiness Probe: không route traffic khi chưa sẵn sàng
- Startup Probe: cho slow-start application
- HTTP, TCP, gRPC, Exec probe types
- Tuning probe parameters

**Output đạt được:** ✅ Ứng dụng tự phục hồi, không nhận traffic khi chưa sẵn sàng.

---

## 🌟 Phase 8 — Production Patterns

### Lab 33 — Helm Package Manager
**Thư mục:** `lab-33-helm/`
**Commit:** `lab(33): package and deploy applications with helm charts`

**Bạn sẽ học được:**
- Helm là gì: Chart, Release, Repository
- Tạo Helm chart từ đầu
- Values, Templates, Helpers
- Helm hooks và test
- Publish chart lên OCI registry

**Output đạt được:** ✅ Đóng gói ứng dụng thành Helm chart, deploy/upgrade/rollback bằng Helm.

---

### Lab 34 — GitOps với ArgoCD
**Thư mục:** `lab-34-gitops-argocd/`
**Commit:** `lab(34): implement gitops workflow with argocd`

**Bạn sẽ học được:**
- GitOps principles (declarative, versioned, automated)
- Cài đặt và cấu hình ArgoCD
- Application, AppProject, ApplicationSet
- Sync policies và auto-heal
- Multi-environment deployment

**Output đạt được:** ✅ Tự động deploy từ Git, mọi thay đổi cluster đều được tracked qua Git history.

---

### Lab 35 — Multi-cluster Management với Cluster API
**Thư mục:** `lab-35-multicluster/`
**Commit:** `lab(35): provision and manage multiple clusters with cluster api`

**Bạn sẽ học được:**
- Cluster API (CAPI) concepts
- Management cluster vs Workload cluster
- Provision cluster mới
- Multi-cluster service discovery
- Federation patterns

**Output đạt được:** ✅ Quản lý nhiều K8s cluster từ một control plane duy nhất.

---

### Lab 36 — CI/CD Pipeline hoàn chỉnh
**Thư mục:** `lab-36-cicd-pipeline/`
**Commit:** `lab(36): build end-to-end cicd pipeline for k8s deployment`

**Bạn sẽ học được:**
- Pipeline: Code → Build → Test → Push Image → Deploy
- GitHub Actions / GitLab CI với K8s
- Kustomize cho environment-specific config
- Canary deployment strategy
- Image promotion workflow

**Output đạt được:** ✅ Pipeline CI/CD hoàn chỉnh từ commit code đến deploy production tự động.

---

## 📁 Cấu Trúc Repository

```
k8sPractices/
├── ROADMAP.md                    # File này
├── lab-01-kubectl-basics/
│   ├── README.md                 # Hướng dẫn chi tiết cho lab
│   └── manifests/                # YAML files
├── lab-02-namespace-context/
│   ├── README.md
│   └── manifests/
├── ...
└── lab-36-cicd-pipeline/
    ├── README.md
    └── manifests/
```

> 💡 **Tip:** Mỗi thư mục `labXX-*/` chứa file `README.md` với hướng dẫn chi tiết từng bước và `manifests/` chứa các file YAML.

---

## 🛠️ Tools Cần Chuẩn Bị

| Tool | Mục đích | Link |
|------|----------|------|
| `kubectl` | Tương tác với cluster | [Install](https://kubernetes.io/docs/tasks/tools/) |
| `minikube` hoặc `kind` | Local cluster | [minikube](https://minikube.sigs.k8s.io/) / [kind](https://kind.sigs.k8s.io/) |
| `helm` | Package manager | [helm.sh](https://helm.sh) |
| `k9s` | Terminal UI cho K8s | [k9scli.io](https://k9scli.io) |
| `kubectx` / `kubens` | Chuyển context/namespace nhanh | [GitHub](https://github.com/ahmetb/kubectx) |
| `stern` | Multi-pod log tailing | [GitHub](https://github.com/stern/stern) |
| Docker Desktop hoặc Podman | Container runtime | |

---

## 📈 Tracking Progress

| Lab | Tên | Status | Commit |
|-----|-----|--------|--------|
| 01 | kubectl basics | ⬜ Todo | - |
| 02 | Namespace & Context | ⬜ Todo | - |
| 03 | Pod Lifecycle | ⬜ Todo | - |
| 04 | Multi-container Pod | ⬜ Todo | - |
| 05 | ReplicaSet | ⬜ Todo | - |
| 06 | Deployment | ⬜ Todo | - |
| 07 | DaemonSet | ⬜ Todo | - |
| 08 | StatefulSet | ⬜ Todo | - |
| 09 | Job & CronJob | ⬜ Todo | - |
| 10 | Service Types | ⬜ Todo | - |
| 11 | DNS & Discovery | ⬜ Todo | - |
| 12 | Ingress | ⬜ Todo | - |
| 13 | NetworkPolicy | ⬜ Todo | - |
| 14 | Endpoints | ⬜ Todo | - |
| 15 | ConfigMap | ⬜ Todo | - |
| 16 | Secret | ⬜ Todo | - |
| 17 | PV & PVC | ⬜ Todo | - |
| 18 | StorageClass | ⬜ Todo | - |
| 19 | Resource Management | ⬜ Todo | - |
| 20 | HPA | ⬜ Todo | - |
| 21 | VPA | ⬜ Todo | - |
| 22 | Scheduling | ⬜ Todo | - |
| 23 | PDB | ⬜ Todo | - |
| 24 | CRD & Operator | ⬜ Todo | - |
| 25 | RBAC | ⬜ Todo | - |
| 26 | Pod Security | ⬜ Todo | - |
| 27 | Zero-trust Network | ⬜ Todo | - |
| 28 | External Secrets | ⬜ Todo | - |
| 29 | Logging EFK | ⬜ Todo | - |
| 30 | Prometheus & Grafana | ⬜ Todo | - |
| 31 | Distributed Tracing | ⬜ Todo | - |
| 32 | Health Probes | ⬜ Todo | - |
| 33 | Helm | ⬜ Todo | - |
| 34 | GitOps ArgoCD | ⬜ Todo | - |
| 35 | Multi-cluster | ⬜ Todo | - |
| 36 | CI/CD Pipeline | ⬜ Todo | - |

> Update status: ⬜ Todo → 🔄 In Progress → ✅ Done

---

*Happy Learning! 🎉 Kubernetes mastery is a journey, not a destination.*
