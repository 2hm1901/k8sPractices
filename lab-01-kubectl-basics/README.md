# Lab 01 — kubectl Basics & Cluster Info

## 🎯 Mục tiêu (Objectives)

Sau lab này, bạn sẽ có thể:
- Xác minh cài đặt `kubectl` và kết nối tới cluster
- Hiểu kiến trúc Kubernetes cluster (Control Plane + Worker Nodes)
- Sử dụng thành thạo các lệnh `kubectl` cơ bản để khám phá cluster
- Hiểu cấu trúc file `kubeconfig` và cách quản lý nhiều cluster
- Thiết lập autocomplete và aliases để tăng tốc độ làm việc

---

## 📋 Prerequisites

- Đã cài đặt `kubectl` (v1.28+ recommended)
- Có một Kubernetes cluster đang chạy:
  - **Local**: [minikube](https://minikube.sigs.k8s.io/), [kind](https://kind.sigs.k8s.io/), [k3d](https://k3d.io/)
  - **Cloud**: GKE, EKS, AKS
- Terminal với shell: `bash` hoặc `zsh`

### Kiểm tra kubectl đã cài chưa:
```bash
kubectl version --client
# Output mong đợi:
# Client Version: v1.28.x
# Kustomize Version: v5.x.x
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Kiến trúc Kubernetes Cluster

```
┌─────────────────────────────────────────────────────────────────┐
│                        CONTROL PLANE                            │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │  API Server  │  │  Scheduler   │  │  Controller Manager  │  │
│  │(kube-apisvr) │  │(kube-sched.) │  │  (kube-ctrl-mgr)     │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────────────────┘  │
│         │                 │                                     │
│  ┌──────▼───────┐  ┌──────▼───────┐                            │
│  │     etcd     │  │  cloud-ctrl  │                            │
│  │  (database)  │  │  (optional)  │                            │
│  └──────────────┘  └──────────────┘                            │
└─────────────────────────┬───────────────────────────────────────┘
                          │ (kubectl talks to API Server)
          ┌───────────────┼────────────────┐
          │               │                │
┌─────────▼──────┐ ┌──────▼───────┐ ┌─────▼────────┐
│  Worker Node 1 │ │ Worker Node 2│ │ Worker Node 3│
│                │ │              │ │              │
│  ┌──────────┐  │ │  ┌────────┐  │ │  ┌────────┐ │
│  │  kubelet │  │ │  │kubelet │  │ │  │kubelet │ │
│  ├──────────┤  │ │  ├────────┤  │ │  ├────────┤ │
│  │kube-proxy│  │ │  │k-proxy │  │ │  │k-proxy │ │
│  ├──────────┤  │ │  ├────────┤  │ │  ├────────┤ │
│  │  Pod     │  │ │  │  Pod   │  │ │  │  Pod   │ │
│  │  Pod     │  │ │  │  Pod   │  │ │  │  Pod   │ │
│  └──────────┘  │ │  └────────┘  │ │  └────────┘ │
└────────────────┘ └──────────────┘ └─────────────┘
```

**Vai trò của từng thành phần:**

| Component | Vai trò |
|-----------|---------|
| **API Server** | "Cửa ngõ" của cluster - mọi request đều qua đây |
| **etcd** | Database lưu trữ toàn bộ state của cluster |
| **Scheduler** | Quyết định Pod sẽ chạy ở Node nào |
| **Controller Manager** | Đảm bảo desired state = actual state |
| **kubelet** | Agent chạy trên mỗi Node, quản lý Pod |
| **kube-proxy** | Quản lý network rules trên mỗi Node |

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Kiểm tra kết nối tới Cluster

```bash
# Xem thông tin cluster đang kết nối
kubectl cluster-info

# Output ví dụ:
# Kubernetes control plane is running at https://127.0.0.1:6443
# CoreDNS is running at https://127.0.0.1:6443/api/v1/namespaces/...

# Xem version của cả client và server
kubectl version

# Chỉ xem client version
kubectl version --client

# Xem version ngắn gọn hơn
kubectl version --short 2>/dev/null || kubectl version
```

### Step 2: Khám phá Nodes

```bash
# Liệt kê tất cả nodes
kubectl get nodes

# Xem chi tiết hơn (IP, OS, kernel version)
kubectl get nodes -o wide

# Output mẫu:
# NAME           STATUS   ROLES           AGE   VERSION   INTERNAL-IP    OS-IMAGE
# minikube       Ready    control-plane   10d   v1.28.3   192.168.49.2   Ubuntu 22.04

# Mô tả chi tiết một node cụ thể
kubectl describe node <node-name>

# Ví dụ với minikube:
kubectl describe node minikube

# Xem labels của nodes
kubectl get nodes --show-labels

# Xem nodes dưới dạng JSON
kubectl get nodes -o json

# Xem nodes dưới dạng YAML
kubectl get nodes -o yaml

# Lọc thông tin cụ thể với JSONPath
kubectl get nodes -o jsonpath='{.items[*].metadata.name}'
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.nodeInfo.kubeletVersion}{"\n"}{end}'
```

### Step 3: Khám phá Namespaces

```bash
# Liệt kê tất cả namespaces
kubectl get namespaces
# hoặc viết tắt:
kubectl get ns

# Output mẫu:
# NAME              STATUS   AGE
# default           Active   10d
# kube-node-lease   Active   10d
# kube-public       Active   10d
# kube-system       Active   10d

# Xem pods trong namespace kube-system (system pods)
kubectl get pods -n kube-system

# Xem pods trong TẤT CẢ namespaces
kubectl get pods --all-namespaces
# hoặc:
kubectl get pods -A
```

**Ý nghĩa các namespace mặc định:**
- `default` — Namespace mặc định khi không chỉ định
- `kube-system` — Chứa các system components (coredns, kube-proxy, ...)
- `kube-public` — Accessible by all users, chứa cluster info
- `kube-node-lease` — Chứa Lease objects cho node heartbeats

### Step 4: Khám phá API Resources

```bash
# Liệt kê TẤT CẢ resource types trong cluster
kubectl api-resources

# Liệt kê với namespace info
kubectl api-resources --namespaced=true   # chỉ resources có namespace
kubectl api-resources --namespaced=false  # chỉ cluster-scoped resources

# Tìm resources theo API group
kubectl api-resources --api-group=apps
kubectl api-resources --api-group=batch

# Liệt kê API versions
kubectl api-versions

# Output mẫu (một phần):
# NAME                  SHORTNAMES  APIVERSION  NAMESPACED  KIND
# pods                  po          v1          true        Pod
# services              svc         v1          true        Service
# deployments           deploy      apps/v1     true        Deployment
```

### Step 5: Sử dụng `kubectl explain`

```bash
# Giải thích cấu trúc của Pod resource
kubectl explain pod

# Giải thích một field cụ thể
kubectl explain pod.spec
kubectl explain pod.spec.containers
kubectl explain pod.spec.containers.ports

# Xem toàn bộ cấu trúc (recursive)
kubectl explain pod --recursive

# Giải thích Deployment
kubectl explain deployment.spec.strategy
```

### Step 6: Hiểu cấu trúc kubeconfig

```bash
# Xem nội dung kubeconfig hiện tại
kubectl config view

# Xem kubeconfig đầy đủ (bao gồm credentials)
kubectl config view --raw

# File kubeconfig mặc định nằm tại:
cat ~/.kube/config
```

**Cấu trúc kubeconfig:**
```yaml
apiVersion: v1
kind: Config
# ─── Clusters ───────────────────────────────────────
clusters:
- cluster:
    certificate-authority-data: <base64-cert>
    server: https://127.0.0.1:6443   # API Server endpoint
  name: my-cluster                   # Tên cluster

# ─── Users ──────────────────────────────────────────
users:
- name: my-user
  user:
    client-certificate-data: <base64>
    client-key-data: <base64>

# ─── Contexts ───────────────────────────────────────
# Context = cluster + user + namespace
contexts:
- context:
    cluster: my-cluster
    namespace: default
    user: my-user
  name: my-context

# ─── Current Context ────────────────────────────────
current-context: my-context
```

```bash
# Xem context hiện tại
kubectl config current-context

# Liệt kê tất cả contexts
kubectl config get-contexts

# Chuyển context
kubectl config use-context <context-name>

# Xem clusters
kubectl config get-clusters

# Xem users
kubectl config get-users
```

### Step 7: Các lệnh get hữu ích khác

```bash
# Xem tất cả resources trong một namespace
kubectl get all -n default
kubectl get all -n kube-system

# Xem events trong cluster (rất hữu ích để debug)
kubectl get events
kubectl get events --sort-by='.lastTimestamp'
kubectl get events -n kube-system

# Xem resource usage của nodes (cần metrics-server)
kubectl top nodes

# Xem resource usage của pods
kubectl top pods
kubectl top pods -A
```

---

## ⚡ Thiết lập Autocomplete & Aliases

### Autocomplete cho bash:
```bash
# Cài đặt bash-completion trước (macOS)
brew install bash-completion@2

# Thêm vào ~/.bashrc hoặc ~/.bash_profile:
source <(kubectl completion bash)
alias k=kubectl
complete -o default -F __start_kubectl k
```

### Autocomplete cho zsh:
```bash
# Thêm vào ~/.zshrc:
source <(kubectl completion zsh)
alias k=kubectl
compdef __start_kubectl k

# Reload:
source ~/.zshrc
```

### Useful Aliases:
```bash
# Thêm vào ~/.bashrc hoặc ~/.zshrc:

# Basic shortcuts
alias k='kubectl'
alias kg='kubectl get'
alias kd='kubectl describe'
alias kdel='kubectl delete'
alias ka='kubectl apply -f'
alias kl='kubectl logs'
alias ke='kubectl exec -it'

# Get shortcuts
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kgpw='kubectl get pods -w'     # watch mode
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kgns='kubectl get ns'
alias kgd='kubectl get deployments'

# Namespace shortcuts
alias kn='kubectl config set-context --current --namespace'

# Quick namespace switch function
kns() {
  kubectl config set-context --current --namespace="$1"
}

# Reload aliases
source ~/.zshrc  # hoặc source ~/.bashrc
```

### Thử ngay sau khi set aliases:
```bash
# Thay vì:
kubectl get pods --all-namespaces
# Dùng:
kgpa

# Thay vì:
kubectl describe pod my-pod
# Dùng:
kd pod my-pod
```

---

## ✅ Kiểm tra kết quả (Verification)

Chạy các lệnh sau và kiểm tra output:

```bash
# 1. Cluster kết nối OK
kubectl cluster-info
# ✅ Phải thấy URL của API server

# 2. Nodes ở trạng thái Ready
kubectl get nodes
# ✅ Tất cả nodes phải có STATUS = Ready

# 3. System pods đang chạy
kubectl get pods -n kube-system
# ✅ Tất cả pods phải ở trạng thái Running hoặc Completed

# 4. API resources hiển thị đầy đủ
kubectl api-resources | wc -l
# ✅ Phải có hơn 50 dòng

# 5. Explain hoạt động
kubectl explain pod.spec.containers.image
# ✅ Phải hiển thị description của field `image`

# 6. Autocomplete hoạt động (gõ rồi nhấn Tab)
kubectl get po<TAB>
# ✅ Phải auto-complete thành "kubectl get pods"
```

---

## 💡 Tips & Gotchas

### ⚠️ Gotcha 1: Namespace mặc định
> Nếu bạn không chỉ định `-n <namespace>`, kubectl luôn dùng namespace `default`. Hãy cẩn thận khi deploy!

```bash
# Sai - deploy vào default namespace
kubectl apply -f my-app.yaml

# Đúng - chỉ định namespace rõ ràng
kubectl apply -f my-app.yaml -n my-app-namespace
```

### ⚠️ Gotcha 2: kubeconfig nhiều cluster
```bash
# Nếu có nhiều cluster, kiểm tra context hiện tại trước khi chạy lệnh quan trọng!
kubectl config current-context

# Dùng KUBECONFIG env var để load nhiều config file
export KUBECONFIG=~/.kube/config:~/.kube/prod-config
```

### 💡 Tip: `-o wide` luôn hữu ích hơn
```bash
# Luôn thêm -o wide để thấy thêm thông tin
kubectl get pods -o wide      # Thấy NODE, IP
kubectl get nodes -o wide     # Thấy OS, kernel, container runtime
```

### 💡 Tip: Dry-run để tạo YAML template
```bash
# Tạo YAML template mà không thực sự deploy
kubectl run nginx --image=nginx --dry-run=client -o yaml
kubectl create deployment nginx --image=nginx --dry-run=client -o yaml
```

### 💡 Tip: `--watch` để theo dõi real-time
```bash
kubectl get pods --watch
# hoặc
kubectl get pods -w
```

---

## 🧹 Dọn dẹp (Cleanup)

Lab này chỉ chạy read-only commands, không cần cleanup tài nguyên. Tuy nhiên:

```bash
# Nếu bạn đã tạo test resources nào đó, xóa chúng:
kubectl delete pod <pod-name>

# Hoặc xóa tất cả trong default namespace (NGUY HIỂM - chỉ dùng trên cluster test):
# kubectl delete all --all -n default
```

---

## 📚 Tham khảo (References)

- [kubectl Cheat Sheet - Official](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [kubectl Overview](https://kubernetes.io/docs/reference/kubectl/overview/)
- [Kubernetes Components](https://kubernetes.io/docs/concepts/overview/components/)
- [Configure kubectl](https://kubernetes.io/docs/tasks/tools/configure-kubectl-linux/)
- [kubeconfig documentation](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)

---

## 🔗 Next Lab

➡️ **[Lab 02 — Namespace & Context](../lab-02-namespace-context/README.md)**

Trong lab tiếp theo, bạn sẽ học cách tạo và quản lý Namespaces, làm việc với nhiều contexts, và sử dụng các tool như `kubens` / `kubectx` để chuyển đổi nhanh giữa các môi trường.
