# Lab 34 — GitOps with ArgoCD

## 🎯 Mục tiêu (Objectives)

Sau khi hoàn thành lab này, bạn sẽ:
- Hiểu các nguyên tắc GitOps và tại sao nó là tiêu chuẩn trong production
- Cài đặt và cấu hình ArgoCD hoàn chỉnh
- Tạo và quản lý ArgoCD `Application`, `AppProject`, `ApplicationSet`
- Triển khai đa môi trường (dev/staging/prod) với ApplicationSet
- Sử dụng Sync Waves và Hooks để kiểm soát thứ tự deploy
- Cấu hình Health Checks tùy chỉnh
- Tích hợp ArgoCD Image Updater để tự động cập nhật image
- Thực hiện Rollback bằng ArgoCD

---

## 📋 Prerequisites

- Lab 33 (Helm) đã hoàn thành
- `kubectl` configured với cluster
- `helm` v3.12+
- `argocd` CLI: `brew install argocd`
- Git repository (GitHub/GitLab) để lưu manifests

```bash
# Verify tools
kubectl version --client
helm version
argocd version --client
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### GitOps — 4 Nguyên tắc (CNCF)

```
┌──────────────────────────────────────────────────────────────┐
│                    GITOPS PRINCIPLES                          │
│                                                              │
│  1. DECLARATIVE    Toàn bộ hệ thống được mô tả khai báo     │
│                    (K8s YAML, Helm values, Kustomize)        │
│                                                              │
│  2. VERSIONED      Git là single source of truth            │
│                    Mọi thay đổi = git commit                 │
│                                                              │
│  3. AUTOMATED      Approved changes tự động apply           │
│                    Không cần manual kubectl apply            │
│                                                              │
│  4. CONTINUOUSLY   Software agents liên tục đảm bảo         │
│     RECONCILED     actual state = desired state              │
└──────────────────────────────────────────────────────────────┘
```

### ArgoCD Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   ARGOCD ARCHITECTURE                        │
│                                                             │
│  Git Repo          ArgoCD (in-cluster)      Target Cluster  │
│  ────────          ───────────────────      ──────────────  │
│                                                             │
│  manifests/ ──►  Repo Server              ──► API Server   │
│  (YAML/Helm/       (clone & render)           (apply K8s   │
│   Kustomize)                                   resources)  │
│                  App Controller                             │
│                  (reconcile loop)                           │
│                  (compare desired                           │
│                   vs actual state)                          │
│                                                             │
│                  API Server                                 │
│                  (REST API + gRPC                           │
│                   WebSocket UI)                             │
│                                                             │
│                  Dex (OIDC)                                 │
│                  (SSO integration)                          │
│                                                             │
│                  Redis (cache)                              │
└─────────────────────────────────────────────────────────────┘
```

### ArgoCD Application States

```
UNKNOWN ──► SYNCED ──► HEALTHY   ← Trạng thái lý tưởng
              │
              ▼
           OutOfSync ──► (auto-sync nếu được cấu hình)
              │
              ▼
           Degraded  ──► Health check fail → alert
```

### So sánh Deployment Strategies

| Phương pháp | Push-based | Pull-based (GitOps) |
|-------------|-----------|---------------------|
| Trigger | CI pipeline push | ArgoCD pull từ Git |
| Cluster access | CI có credentials | Chỉ ArgoCD trong cluster |
| Audit trail | CI logs | Git history |
| Drift detection | Không | Có (tự động) |
| Rollback | Re-run pipeline | `git revert` hoặc UI |

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Cài đặt ArgoCD

```bash
# Tạo namespace
kubectl create namespace argocd

# Cài đặt ArgoCD (stable manifest)
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Hoặc dùng Helm (production-ready hơn)
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f manifests/argocd-install-values.yaml \
  --wait

# Theo dõi pods khởi động
kubectl get pods -n argocd -w
```

### Step 2: Truy cập ArgoCD UI

```bash
# Lấy initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Port-forward UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Mở browser: https://localhost:8080
# Username: admin
# Password: (từ lệnh trên)

# Login bằng CLI
argocd login localhost:8080 \
  --username admin \
  --password <PASSWORD> \
  --insecure

# Đổi password ngay (quan trọng!)
argocd account update-password
```

### Step 3: Tạo AppProject (RBAC)

AppProject giới hạn Application trong phạm vi được phép:

```bash
# Tạo AppProject
kubectl apply -f manifests/argocd-appproject.yaml

# Kiểm tra
argocd proj list
argocd proj get my-project

# Xem RBAC roles
argocd proj role list my-project
```

```yaml
# manifests/argocd-appproject.yaml (xem file thực tế)
# - Cho phép deploy từ repo GitHub của bạn
# - Chỉ vào namespaces: dev, staging, prod
# - Whitelist resource types được phép tạo
```

### Step 4: Tạo ArgoCD Application

```bash
# Áp dụng Application manifest
kubectl apply -f manifests/argocd-application.yaml

# Hoặc tạo bằng CLI
argocd app create my-webapp \
  --project my-project \
  --repo https://github.com/YOUR_ORG/k8s-manifests \
  --path apps/my-webapp/overlays/dev \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace dev \
  --sync-policy automated \
  --auto-prune \
  --self-heal

# Xem trạng thái
argocd app get my-webapp
argocd app list
```

### Step 5: Sync Application

```bash
# Manual sync
argocd app sync my-webapp

# Sync với prune (xóa orphaned resources)
argocd app sync my-webapp --prune

# Sync chỉ một số resources
argocd app sync my-webapp \
  --resource apps:Deployment:my-webapp

# Xem sync status
argocd app wait my-webapp --health --timeout 120

# Xem logs của sync operation
argocd app logs my-webapp
```

### Step 6: ApplicationSet — Đa môi trường

ApplicationSet tự động tạo nhiều Applications từ một template:

```bash
# Deploy ApplicationSet
kubectl apply -f manifests/argocd-applicationset.yaml

# Kiểm tra các Applications được tạo ra
argocd app list | grep my-webapp

# Output:
# my-webapp-dev       Synced   Healthy
# my-webapp-staging   Synced   Healthy
# my-webapp-prod      OutOfSync Healthy  ← cần manual sync cho prod
```

### Step 7: Sync Waves và Hooks

Kiểm soát thứ tự deploy với annotations:

```yaml
# Wave: resource với wave thấp hơn deploy trước
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"   # Deploy sau wave "0"
```

```yaml
# Hook: chạy Job vào các điểm cụ thể
metadata:
  annotations:
    argocd.argoproj.io/hook: PreSync         # Chạy trước sync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
```

**Thứ tự thực thi:**
```
PreSync hooks → Wave 0 → Wave 1 → ... → PostSync hooks → SyncFail hooks (nếu lỗi)
```

```bash
# Ví dụ deployment order trong manifests:
# Wave -1: Namespace, RBAC (argocd.argoproj.io/sync-wave: "-1")
# Wave  0: ConfigMap, Secret (default)
# Wave  1: Deployment, StatefulSet
# Wave  2: Service, Ingress
# Wave  5: Smoke test Job (post-deploy verification)
```

### Step 8: Health Checks

ArgoCD có built-in health checks cho standard resources. Thêm custom health check:

```lua
-- Custom health check cho CRD (Lua script)
-- Đặt trong argocd-cm ConfigMap
hs = {}
if obj.status ~= nil then
  if obj.status.phase == "Running" then
    hs.status = "Healthy"
    hs.message = "Application is running"
    return hs
  end
  if obj.status.phase == "Failed" then
    hs.status = "Degraded"
    hs.message = obj.status.message
    return hs
  end
end
hs.status = "Progressing"
hs.message = "Waiting for status"
return hs
```

```bash
# Cấu hình trong argocd-cm
kubectl edit configmap argocd-cm -n argocd

# Hoặc patch:
kubectl patch configmap argocd-cm -n argocd --patch '
data:
  resource.customizations.health.myorg.io_MyApp: |
    hs = {}
    if obj.status.ready then
      hs.status = "Healthy"
    else
      hs.status = "Progressing"
    end
    return hs
'
```

### Step 9: ArgoCD Image Updater

Tự động cập nhật image version trong Git khi có image mới:

```bash
# Cài đặt Image Updater
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml

# Annotate Application để theo dõi image
kubectl annotate application my-webapp -n argocd \
  argocd-image-updater.argoproj.io/image-list="myapp=ghcr.io/myorg/myapp" \
  argocd-image-updater.argoproj.io/myapp.update-strategy="semver" \
  argocd-image-updater.argoproj.io/myapp.allow-tags="regexp:^v[0-9]+\.[0-9]+\.[0-9]+$" \
  argocd-image-updater.argoproj.io/write-back-method="git"

# Image Updater sẽ tự động:
# 1. Kiểm tra registry cho image mới
# 2. Cập nhật values.yaml trong Git
# 3. ArgoCD sync sẽ deploy version mới
```

### Step 10: Rollback với ArgoCD

```bash
# Xem history của application
argocd app history my-webapp

# Output:
# ID  DATE       REVISION  AUTHOR  MESSAGE
# 1   2024-01-01 a1b2c3d   ci-bot  feat: update image to v1.0.1
# 2   2024-01-02 e4f5g6h   ci-bot  feat: update image to v1.0.2

# Rollback về revision cụ thể
argocd app rollback my-webapp 1

# Hoặc rollback về Git commit cụ thể
argocd app sync my-webapp --revision a1b2c3d

# Sau rollback, disable auto-sync để tránh bị override
argocd app set my-webapp --sync-policy none
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# Kiểm tra tất cả Applications
argocd app list

# Kiểm tra health và sync status
argocd app get my-webapp-dev
argocd app get my-webapp-staging
argocd app get my-webapp-prod

# Verify resources được sync
kubectl get all -n dev -l "app.kubernetes.io/managed-by=Helm"
kubectl get all -n staging
kubectl get all -n prod

# Kiểm tra ArgoCD metrics
kubectl get --raw /metrics -n argocd 2>/dev/null | grep argocd_app

# Xem events
kubectl get events -n argocd --sort-by='.lastTimestamp'

# Check drift detection (nếu có OutOfSync)
argocd app diff my-webapp
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xóa Applications (ArgoCD sẽ cascade delete K8s resources)
argocd app delete my-webapp-dev --cascade
argocd app delete my-webapp-staging --cascade
argocd app delete my-webapp-prod --cascade

# Xóa ApplicationSet (tự động xóa các Applications con)
kubectl delete applicationset my-webapp-appset -n argocd

# Xóa AppProject
argocd proj delete my-project

# Uninstall ArgoCD hoàn toàn
helm uninstall argocd -n argocd
kubectl delete namespace argocd

# Hoặc xóa bằng manifest
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl delete namespace argocd
```

---

## 💡 Tips & Gotchas

### ⚠️ Các vấn đề thường gặp

1. **Auto-sync vô tình xóa resources** — Dùng `--auto-prune` cẩn thận:
   ```yaml
   # Chỉ bật prune khi đã confident
   syncPolicy:
     automated:
       prune: true      # Cẩn thận! Xóa resources không còn trong Git
       selfHeal: true
   ```

2. **ignoreDifferences** — Bỏ qua các field thay đổi liên tục:
   ```yaml
   ignoreDifferences:
   - group: apps
     kind: Deployment
     jsonPointers:
     - /spec/replicas    # HPA thay đổi replicas → bỏ qua
   ```

3. **Resource tracking** — ArgoCD dùng label hoặc annotation để track:
   ```bash
   # Mặc định dùng label
   kubectl label deployment my-app app.kubernetes.io/instance=my-webapp
   ```

4. **Private Git repos** — Thêm credentials:
   ```bash
   argocd repo add https://github.com/myorg/private-repo \
     --username git \
     --password $GITHUB_TOKEN
   ```

5. **Avoid "argo-cd" in app names** — tên application phải unique trong cluster.

### 💡 Production Best Practices

- Luôn dùng `AppProject` để phân quyền theo team
- Enable OIDC/SSO (Dex + GitHub OAuth) thay vì local users
- Sử dụng `ApplicationSet` + `cluster-generator` cho multi-cluster
- Monitor với Prometheus metrics: `argocd_app_info`, `argocd_app_sync_total`
- Backup etcd và ArgoCD configs định kỳ
- Dùng `--server-side` apply để tránh annotation quá lớn

---

## 📚 Tham khảo (References)

- [ArgoCD Official Docs](https://argo-cd.readthedocs.io/)
- [ArgoCD ApplicationSet](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [ArgoCD Image Updater](https://argocd-image-updater.readthedocs.io/)
- [GitOps Principles — OpenGitOps](https://opengitops.dev/)
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)

---

## 🔗 Next Lab

➡️ **[Lab 35 — Multi-cluster Management](../lab-35-multicluster/README.md)**

Quản lý nhiều Kubernetes clusters với Cluster API, ArgoCD multi-cluster, và Submariner.
