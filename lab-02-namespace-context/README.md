# Lab 02 — Namespace & Context

## 🎯 Mục tiêu (Objectives)

Sau lab này, bạn sẽ có thể:
- Giải thích được **Namespace** là gì và tại sao cần dùng trong môi trường thực tế
- Tạo và quản lý Namespaces theo cả hai cách: **imperative** và **declarative**
- Thành thạo `kubectl config` để quản lý **contexts** và chuyển đổi cluster/namespace
- Làm việc với resources **across namespaces**
- Cài đặt và sử dụng **kubens** / **kubectx** để tăng tốc workflow

---

## 📋 Prerequisites

- Đã hoàn thành [Lab 01 — kubectl Basics](../lab-01-kubectl-basics/README.md)
- `kubectl` đã cài và kết nối cluster thành công
- (Optional) Homebrew để cài `kubens`/`kubectx` (macOS/Linux)

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Namespace là gì?

Namespace là cơ chế **phân tách logic** trong một Kubernetes cluster. Hãy nghĩ về nó như các "phòng ban" trong một công ty — cùng chung hạ tầng nhưng có ranh giới riêng.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                           │
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌───────────────┐   │
│  │  Namespace: dev │  │Namespace:staging│  │Namespace: prod│   │
│  │                 │  │                 │  │               │   │
│  │ ┌─────────────┐ │  │ ┌─────────────┐ │  │ ┌───────────┐ │   │
│  │ │  web:latest │ │  │ │ web:v1.2-rc │ │  │ │ web:v1.1  │ │   │
│  │ │  db:dev     │ │  │ │ db:staging  │ │  │ │ db:prod   │ │   │
│  │ └─────────────┘ │  │ └─────────────┘ │  │ └───────────┘ │   │
│  │                 │  │                 │  │               │   │
│  │ ResourceQuota:  │  │ ResourceQuota:  │  │ ResourceQuota:│   │
│  │ CPU: 2, RAM: 4G │  │ CPU: 4, RAM: 8G │  │ CPU: 16, 32G │   │
│  └─────────────────┘  └─────────────────┘  └───────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Namespace: kube-system (Cluster-wide components)       │    │
│  │  coredns | kube-proxy | metrics-server | ...            │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### Tại sao dùng Namespace?

| Lý do | Ví dụ thực tế |
|-------|--------------|
| **Môi trường phân tách** | `dev`, `staging`, `production` trên cùng cluster |
| **Team isolation** | Team A không thấy resources của Team B |
| **Resource Quotas** | Giới hạn CPU/RAM per namespace |
| **RBAC** | Phân quyền chi tiết theo namespace |
| **Network Policies** | Kiểm soát traffic giữa namespaces |
| **Tổ chức gọn gàng** | Tránh name collision (mỗi ns có service "nginx") |

### Điều gì KHÔNG phân tách được qua Namespace?

- **Nodes** — Cluster-scoped resource
- **PersistentVolumes** — Cluster-scoped
- **StorageClasses** — Cluster-scoped
- **ClusterRoles** — Cluster-scoped
- **Network** — Pods giữa các namespace vẫn có thể giao tiếp (trừ khi có NetworkPolicy)

### Context là gì?

```
Context = Cluster + User + Namespace (default)

┌──────────────────────────────────────────────────┐
│                kubeconfig file                   │
│                                                  │
│  Cluster "production"  ←──┐                      │
│  Cluster "staging"     ←──┤                      │
│  Cluster "local"       ←──┤                      │
│                           │                      │
│  User "admin"          ←──┤                      │
│  User "developer"      ←──┤                      │
│                           │                      │
│  Context "prod-ctx" ──────┤                      │
│    cluster: production    │                      │
│    user: admin            │                      │
│    namespace: default     │                      │
│                           │                      │
│  Context "dev-ctx" ───────┘                      │
│    cluster: local                                │
│    user: developer                               │
│    namespace: dev                                │
│                                                  │
│  current-context: dev-ctx  ◄── đang dùng cái này│
└──────────────────────────────────────────────────┘
```

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Khám phá Namespaces hiện có

```bash
# Liệt kê tất cả namespaces
kubectl get namespaces
# hoặc viết tắt
kubectl get ns

# Output mẫu:
# NAME              STATUS   AGE
# default           Active   10d
# kube-node-lease   Active   10d
# kube-public       Active   10d
# kube-system       Active   10d

# Xem chi tiết một namespace
kubectl describe ns default

# Output sẽ thấy: Labels, Annotations, Status, ResourceQuota, LimitRange
```

### Step 2: Tạo Namespace — Imperative (lệnh trực tiếp)

```bash
# Tạo namespace đơn giản
kubectl create namespace development
kubectl create namespace staging
kubectl create namespace production

# Kiểm tra
kubectl get ns

# Xem labels
kubectl get ns --show-labels
```

### Step 3: Tạo Namespace — Declarative (từ YAML file)

```bash
# Apply các file manifest đã chuẩn bị
kubectl apply -f manifests/namespace-dev.yaml
kubectl apply -f manifests/namespace-staging.yaml
kubectl apply -f manifests/namespace-prod.yaml

# Apply tất cả cùng lúc
kubectl apply -f manifests/

# Kiểm tra kết quả
kubectl get ns
kubectl describe ns dev
kubectl describe ns staging
kubectl describe ns prod
```

### Step 4: Deploy resources vào các Namespaces khác nhau

```bash
# Tạo một pod trong namespace dev
kubectl run nginx-dev --image=nginx:alpine -n dev

# Tạo pod trong namespace staging
kubectl run nginx-staging --image=nginx:alpine -n staging

# Tạo pod trong namespace prod
kubectl run nginx-prod --image=nginx:alpine -n prod

# Xem pods theo từng namespace
kubectl get pods -n dev
kubectl get pods -n staging
kubectl get pods -n prod

# Xem pods TẤT CẢ namespaces
kubectl get pods -A
kubectl get pods --all-namespaces

# Output mẫu:
# NAMESPACE   NAME            READY   STATUS    RESTARTS   AGE
# dev         nginx-dev       1/1     Running   0          1m
# staging     nginx-staging   1/1     Running   0          1m
# prod        nginx-prod      1/1     Running   0          1m
```

### Step 5: DNS cross-namespace

Trong Kubernetes, service DNS follow format: `<service-name>.<namespace>.svc.cluster.local`

```bash
# Tạo service trong dev namespace
kubectl expose pod nginx-dev --port=80 -n dev --name=nginx-svc

# Từ pod trong namespace khác, có thể reach được via full DNS:
kubectl run test-pod --image=busybox -it --rm -n staging \
  -- wget -qO- http://nginx-svc.dev.svc.cluster.local

# Trong cùng namespace, chỉ cần tên ngắn:
kubectl run test-pod --image=busybox -it --rm -n dev \
  -- wget -qO- http://nginx-svc
```

### Step 6: Quản lý Contexts với kubectl config

```bash
# Xem tất cả contexts
kubectl config get-contexts

# Output mẫu:
# CURRENT   NAME       CLUSTER    AUTHINFO   NAMESPACE
# *         minikube   minikube   minikube   default

# Xem context hiện tại
kubectl config current-context

# Tạo context mới trỏ vào namespace dev
kubectl config set-context dev-context \
  --cluster=minikube \
  --user=minikube \
  --namespace=dev

# Tạo context cho staging
kubectl config set-context staging-context \
  --cluster=minikube \
  --user=minikube \
  --namespace=staging

# Tạo context cho prod  
kubectl config set-context prod-context \
  --cluster=minikube \
  --user=minikube \
  --namespace=prod

# Xem lại danh sách contexts
kubectl config get-contexts

# Chuyển sang context dev
kubectl config use-context dev-context

# Giờ kubectl mặc định làm việc trong namespace dev
kubectl get pods    # Tương đương: kubectl get pods -n dev

# Chuyển sang context staging
kubectl config use-context staging-context
kubectl get pods    # Tương đương: kubectl get pods -n staging

# Chuyển namespace mà không đổi context (temporary)
kubectl config set-context --current --namespace=production
kubectl get pods    # Bây giờ ở production namespace

# Quay về context gốc (minikube)
kubectl config use-context minikube
```

### Step 7: Cài đặt và dùng kubens / kubectx

**kubectx** — chuyển context nhanh
**kubens** — chuyển namespace nhanh

```bash
# Cài đặt trên macOS
brew install kubectx

# kubectx cũng tự động cài kubens

# Hoặc cài thủ công:
# sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx
# sudo ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx
# sudo ln -s /opt/kubectx/kubens /usr/local/bin/kubens

# Sử dụng kubectx:
kubectx               # Liệt kê tất cả contexts, highlight current
kubectx dev-context   # Chuyển sang context tên "dev-context"
kubectx -             # Quay lại context trước (như `cd -`)

# Sử dụng kubens:
kubens                # Liệt kê namespaces, highlight current
kubens dev            # Chuyển sang namespace "dev"
kubens -              # Quay lại namespace trước

# Ví dụ workflow thực tế:
kubectx production-cluster   # Switch sang production cluster
kubens prod                  # Switch sang prod namespace
kubectl get pods             # Xem pods trong prod namespace
```

### Step 8: Làm việc với ResourceQuota trong Namespace

```bash
# Xem quotas đã áp dụng trong namespace dev
kubectl get resourcequota -n dev
kubectl describe resourcequota -n dev

# Xem limit ranges
kubectl get limitrange -n dev
kubectl describe limitrange -n dev

# Thử deploy một pod KHÔNG có resource limits (sẽ bị reject nếu có quota)
kubectl run no-limits --image=nginx -n dev

# Thử deploy một pod với resource limits
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: with-limits
  namespace: dev
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "200m"
        memory: "256Mi"
EOF
```

### Step 9: Xóa Namespace (và toàn bộ resources bên trong)

```bash
# ⚠️ CẢNH BÁO: Xóa namespace sẽ xóa TẤT CẢ resources bên trong!

# Xóa resources thủ công trước (recommended)
kubectl delete pod nginx-dev -n dev
kubectl delete pod nginx-staging -n staging
kubectl delete pod nginx-prod -n prod

# Xóa namespace (sẽ kéo theo tất cả resources còn lại)
kubectl delete ns development
kubectl delete ns staging
kubectl delete ns production

# Xóa từ file manifest
kubectl delete -f manifests/namespace-dev.yaml
kubectl delete -f manifests/namespace-staging.yaml
kubectl delete -f manifests/namespace-prod.yaml

# Kiểm tra (namespace "Terminating" -> sau đó biến mất)
kubectl get ns -w
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# 1. Namespaces đã tạo thành công
kubectl get ns | grep -E 'dev|staging|prod'
# ✅ Phải thấy: dev, staging, prod đều ở trạng thái Active

# 2. Labels được apply đúng
kubectl get ns dev -o yaml | grep -A5 labels
# ✅ Phải thấy labels: environment=development, team=backend

# 3. Pods chạy đúng namespace
kubectl get pods -A | grep -E 'dev|staging|prod'
# ✅ Mỗi pod phải ở đúng namespace của nó

# 4. Contexts đã tạo
kubectl config get-contexts | grep -E 'dev|staging|prod'
# ✅ Phải thấy các contexts đã tạo

# 5. kubens hoạt động
kubens
# ✅ Phải hiển thị list namespaces với current namespace highlighted

# 6. DNS cross-namespace
kubectl run test --image=busybox -it --rm -n staging \
  --restart=Never -- nslookup nginx-svc.dev.svc.cluster.local
# ✅ Phải resolve được IP address
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xóa test pods
kubectl delete pod nginx-dev -n dev --ignore-not-found
kubectl delete pod nginx-staging -n staging --ignore-not-found
kubectl delete pod nginx-prod -n prod --ignore-not-found
kubectl delete pod with-limits -n dev --ignore-not-found

# Xóa services
kubectl delete svc nginx-svc -n dev --ignore-not-found

# Xóa contexts khỏi kubeconfig
kubectl config delete-context dev-context
kubectl config delete-context staging-context
kubectl config delete-context prod-context

# Xóa namespaces (chờ khoảng 30s để terminate)
kubectl delete -f manifests/namespace-dev.yaml --ignore-not-found
kubectl delete -f manifests/namespace-staging.yaml --ignore-not-found
kubectl delete -f manifests/namespace-prod.yaml --ignore-not-found

# Verify cleanup
kubectl get ns
```

---

## 💡 Tips & Gotchas

### ⚠️ Gotcha 1: Namespace "Terminating" mãi không xong
Đôi khi namespace bị stuck ở trạng thái `Terminating`. Nguyên nhân thường do Finalizers.

```bash
# Xem finalizers
kubectl get ns <name> -o yaml | grep finalizers -A 5

# Force remove finalizers (USE WITH CAUTION - production!)
kubectl patch namespace <name> -p '{"metadata":{"finalizers":[]}}' --type=merge
```

### ⚠️ Gotcha 2: Xóa namespace = mất hết data
> Khi xóa một namespace, Kubernetes xóa **TẤT CẢ** resources bên trong, kể cả PersistentVolumeClaims. Hãy backup trước!

### ⚠️ Gotcha 3: Cross-namespace secrets
Secrets KHÔNG tự động share qua namespaces. Nếu cần share secret (như Docker registry credentials), phải tạo lại trong mỗi namespace.

```bash
# Copy secret từ namespace này sang namespace khác
kubectl get secret my-secret -n source-ns -o yaml | \
  sed 's/namespace: source-ns/namespace: dest-ns/' | \
  kubectl apply -f -
```

### 💡 Tip: Đặt namespace mặc định cho context

```bash
# Thay vì gõ -n dev mỗi lần, set default namespace cho context
kubectl config set-context --current --namespace=dev
# Hoặc dùng kubens:
kubens dev
```

### 💡 Tip: Naming conventions cho Namespace

```
# Theo môi trường
dev, staging, production

# Theo team/project
team-frontend, team-backend, team-data

# Kết hợp
frontend-dev, frontend-prod, backend-dev, backend-prod
```

### 💡 Tip: Dùng Labels để organize namespaces

```bash
kubectl label namespace dev \
  environment=development \
  team=backend \
  cost-center=engineering

# Sau đó query theo label
kubectl get ns -l environment=development
```

---

## 📚 Tham khảo (References)

- [Namespaces - Kubernetes Docs](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/)
- [Configure Access to Multiple Clusters](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/)
- [kubectx & kubens - GitHub](https://github.com/ahmetb/kubectx)
- [Namespace Best Practices](https://kubernetes.io/docs/concepts/policy/limit-range/)
- [Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)

---

## 🔗 Next Lab

➡️ **[Lab 03 — Pod Lifecycle & YAML Manifests](../lab-03-pod-lifecycle/README.md)**

Lab tiếp theo sẽ đào sâu vào **Pod** — đơn vị cơ bản nhất của Kubernetes. Bạn sẽ học cách viết YAML manifest từ đầu, hiểu pod lifecycle, và thành thạo các lệnh debugging.
