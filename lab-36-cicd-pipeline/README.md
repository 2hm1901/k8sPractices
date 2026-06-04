# Lab 36 — Full CI/CD Pipeline

## 🎯 Mục tiêu (Objectives)

Sau khi hoàn thành lab này, bạn sẽ:
- Xây dựng pipeline CI/CD end-to-end hoàn chỉnh: Code → Build → Test → Deploy
- Sử dụng GitHub Actions với Docker build, push, và Kubernetes deployment
- Cấu trúc Kustomize với base + overlays (dev/prod) cho environment management
- Triển khai Canary deployment với Argo Rollouts
- Quản lý image promotion giữa các môi trường
- Xử lý secrets an toàn trong CI/CD pipeline
- Áp dụng pipeline security: SLSA, image signing với Cosign

---

## 📋 Prerequisites

- Lab 33–35 đã hoàn thành
- GitHub account + repository
- Docker Hub hoặc GHCR account
- ArgoCD đang chạy (từ Lab 34)
- `kustomize` CLI: `brew install kustomize`
- `cosign`: `brew install cosign`

```bash
# Verify tools
kustomize version
cosign version
kubectl version --client

# Cài Argo Rollouts controller
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f \
  https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# Cài kubectl plugin
brew install argoproj/tap/kubectl-argo-rollouts
kubectl argo rollouts version
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### End-to-End Pipeline Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                    COMPLETE CI/CD PIPELINE                           │
│                                                                      │
│  Developer          CI (GitHub Actions)       GitOps (ArgoCD)        │
│  ─────────          ──────────────────        ─────────────────      │
│                                                                      │
│  git push   ──►  1. Unit Tests                                       │
│                  2. Security Scan (Trivy)                            │
│                  3. Docker Build                                      │
│                  4. Image Sign (Cosign)   ──► GHCR Registry          │
│                  5. Update Helm values    ──► Git (manifests repo)   │
│                                                                      │
│                                          ArgoCD detects change       │
│                                               │                      │
│                                          6. Sync to dev ──► dev ns  │
│                                          7. Run smoke tests          │
│                                          8. Promote to prod          │
│                                          9. Canary (10%→50%→100%)   │
│                                         10. Full rollout / rollback  │
└──────────────────────────────────────────────────────────────────────┘
```

### Kustomize Structure

```
manifests/
├── base/                    # Resources dùng chung cho tất cả envs
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml   # Base kustomization
└── overlays/
    ├── dev/                 # Dev-specific overrides
    │   ├── kustomization.yaml
    │   ├── replica-patch.yaml
    │   └── resource-patch.yaml
    └── prod/                # Prod-specific overrides
        ├── kustomization.yaml
        ├── replica-patch.yaml
        ├── hpa.yaml
        └── pdb.yaml
```

### Canary Deployment Flow

```
Version v1 (100%)
    │
    ▼ Deploy v2
v1 (90%) + v2 (10%)   ← Initial canary step
    │ Wait 5 min, check metrics
    ▼
v1 (50%) + v2 (50%)   ← Scale up canary
    │ Wait 10 min, analyze
    ▼
v2 (100%)             ← Promote to full
    │ OR if error rate > 5%
    ▼
v1 (100%)             ← Auto rollback!
```

### Supply Chain Security (SLSA)

```
SLSA Level 1: Build scripts → provenance generated
SLSA Level 2: Build service → signed provenance
SLSA Level 3: Build service hardened, ephemeral environments
SLSA Level 4: Two-party review + hermetic builds

Tools:
- Cosign: Image signing
- SBOM (Syft): Software Bill of Materials
- Trivy: Vulnerability scanning
- Sigstore/Fulcio: Keyless signing with OIDC
```

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Cấu trúc Kustomize

```bash
# Build Kustomize manifest
kustomize build manifests/base/

# Build với overlay dev
kustomize build manifests/overlays/dev/

# Build với overlay prod
kustomize build manifests/overlays/prod/

# Apply trực tiếp
kustomize build manifests/overlays/dev/ | kubectl apply -f -

# Hoặc dùng kubectl -k
kubectl apply -k manifests/overlays/dev/
kubectl apply -k manifests/overlays/prod/

# Xem diff giữa dev và prod
diff <(kustomize build manifests/overlays/dev/) \
     <(kustomize build manifests/overlays/prod/)
```

### Step 2: GitHub Actions Pipeline

File pipeline `.github/workflows/ci-cd.yaml` thực hiện:

1. **CI (Continuous Integration)**:
   ```bash
   # Lint và test code
   # Build Docker image
   # Scan image với Trivy
   # Sign image với Cosign
   # Push lên GHCR
   ```

2. **CD (Continuous Delivery)**:
   ```bash
   # Update image tag trong Kustomize overlay
   cd manifests/overlays/dev
   kustomize edit set image myapp=ghcr.io/myorg/myapp:${{ github.sha }}
   git commit -am "ci: update dev image to ${{ github.sha }}"
   git push
   # ArgoCD sẽ tự động sync
   ```

```bash
# Xem pipeline đang chạy
gh run list --repo myorg/myapp

# Watch run
gh run watch

# Download artifacts
gh run download <run-id>
```

### Step 3: Thiết lập GitHub Secrets

```bash
# Cần thiết lập các secrets trong GitHub repo:
# Settings → Secrets and variables → Actions

# Cần thiết lập:
# GHCR_TOKEN        : GitHub Personal Access Token với write:packages
# KUBE_CONFIG       : base64 encoded kubeconfig (cho prod cluster)
# ARGOCD_SERVER     : ArgoCD server URL
# ARGOCD_TOKEN      : ArgoCD API token
# SLACK_WEBHOOK     : (optional) Slack notifications

# Encode kubeconfig
base64 -i ~/.kube/config | tr -d '\n' | pbcopy
# Paste vào GitHub Secrets → KUBE_CONFIG

# Tạo ArgoCD token
argocd account generate-token --account ci-bot > argocd-token.txt
# Paste nội dung vào GitHub Secrets → ARGOCD_TOKEN
```

### Step 4: Docker Image Signing với Cosign

```bash
# Keyless signing với OIDC (dùng trong GitHub Actions)
# Không cần quản lý private keys!

# Trong CI pipeline, cosign tự động dùng OIDC token từ GitHub
cosign sign --yes ghcr.io/myorg/myapp:$IMAGE_TAG

# Verify signature
cosign verify ghcr.io/myorg/myapp:$IMAGE_TAG \
  --certificate-identity "https://github.com/myorg/myapp/.github/workflows/ci-cd.yaml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"

# Generate và attach SBOM
syft ghcr.io/myorg/myapp:$IMAGE_TAG -o spdx-json > sbom.json
cosign attach sbom --sbom sbom.json ghcr.io/myorg/myapp:$IMAGE_TAG
cosign sign --yes --attachment sbom ghcr.io/myorg/myapp:$IMAGE_TAG

# Verify trong admission controller (Kyverno policy)
# Chỉ cho phép deploy images đã được ký
```

### Step 5: Canary Deployment với Argo Rollouts

```bash
# Apply Rollout resource (thay thế Deployment)
kubectl apply -f manifests/argo-rollout-canary.yaml -n production

# Xem trạng thái rollout
kubectl argo rollouts get rollout my-webapp -n production --watch

# Trigger rollout mới (update image)
kubectl argo rollouts set image my-webapp \
  my-webapp=ghcr.io/myorg/myapp:v2.0.0 \
  -n production

# Xem chi tiết canary steps
kubectl argo rollouts get rollout my-webapp -n production

# Manual promote (nếu pause ở step)
kubectl argo rollouts promote my-webapp -n production

# Abort rollout (rollback)
kubectl argo rollouts abort my-webapp -n production

# Mở Argo Rollouts Dashboard
kubectl argo rollouts dashboard
# http://localhost:3100
```

### Step 6: AnalysisTemplate — Automated Canary Analysis

```yaml
# AnalysisTemplate dùng Prometheus metrics để quyết định rollout
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate
spec:
  args:
  - name: service-name
  metrics:
  - name: success-rate
    interval: 1m
    successCondition: result[0] >= 0.95   # 95% success rate required
    failureLimit: 3
    provider:
      prometheus:
        address: http://prometheus.monitoring:9090
        query: |
          sum(rate(http_requests_total{service="{{args.service-name}}",status!~"5.."}[5m]))
          /
          sum(rate(http_requests_total{service="{{args.service-name}}"}[5m]))
```

```bash
# Apply analysis template
kubectl apply -f manifests/analysis-template.yaml

# Kiểm tra analysis runs
kubectl get analysisrun -n production
kubectl describe analysisrun <name> -n production
```

### Step 7: Image Promotion giữa môi trường

```bash
# Pattern: Promote image từ dev → staging → prod

# Script promote
#!/bin/bash
SOURCE_ENV=$1    # dev
TARGET_ENV=$2    # staging
IMAGE_TAG=$3     # sha hoặc semver

# Lấy image tag đang dùng ở source env
CURRENT_IMAGE=$(kustomize build manifests/overlays/$SOURCE_ENV | \
  grep "image:" | grep "myapp" | awk '{print $2}')

echo "Promoting $CURRENT_IMAGE from $SOURCE_ENV to $TARGET_ENV"

# Update target overlay
cd manifests/overlays/$TARGET_ENV
kustomize edit set image myapp=$CURRENT_IMAGE

# Commit và push
git add kustomization.yaml
git commit -m "ci: promote $CURRENT_IMAGE to $TARGET_ENV"
git push

echo "Promotion complete. ArgoCD will sync $TARGET_ENV shortly."
```

```bash
# GitHub Actions workflow: manual promotion trigger
# Dùng workflow_dispatch với inputs
# .github/workflows/promote.yaml

# Trigger manual promotion
gh workflow run promote.yaml \
  --field source_env=staging \
  --field target_env=prod \
  --field image_tag=v1.2.3
```

### Step 8: Secret Management trong CI/CD

```bash
# Option 1: External Secrets Operator (production best practice)
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace

# Kết nối với AWS Secrets Manager
kubectl apply -f - <<'EOF'
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secretsmanager
  namespace: production
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
EOF

# Define ExternalSecret
kubectl apply -f - <<'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: production
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secretsmanager
    kind: SecretStore
  target:
    name: db-credentials         # Tên Secret sẽ được tạo trong K8s
  data:
  - secretKey: DB_PASSWORD
    remoteRef:
      key: production/db         # Key trong AWS Secrets Manager
      property: password
EOF
```

```bash
# Option 2: HashiCorp Vault Agent Injector
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "my-app"
    vault.hashicorp.com/agent-inject-secret-config: "secret/data/myapp/config"
spec:
  serviceAccountName: vault-auth
  containers:
  - name: my-app
    image: ghcr.io/myorg/myapp:v1.0.0
EOF

# Option 3: Sealed Secrets (đơn giản hơn)
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system

# Seal một secret
kubectl create secret generic db-creds \
  --from-literal=password=mysecret \
  --dry-run=client -o yaml | \
  kubeseal --format yaml > manifests/overlays/prod/db-creds-sealed.yaml

# SealedSecret an toàn để commit vào Git!
git add manifests/overlays/prod/db-creds-sealed.yaml
git commit -m "feat: add sealed db credentials"
```

### Step 9: Monitoring Pipeline Health

```bash
# Xem pipeline metrics với Prometheus
# argocd_app_sync_total: số lần sync theo status
# argocd_app_info: trạng thái hiện tại của apps

# Alert rules cho pipeline failures
cat <<'EOF' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: argocd-alerts
  namespace: monitoring
spec:
  groups:
  - name: argocd
    rules:
    - alert: ArgoCDAppOutOfSync
      expr: argocd_app_info{sync_status="OutOfSync"} > 0
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "ArgoCD Application {{ $labels.name }} is OutOfSync"
    - alert: ArgoCDAppDegraded
      expr: argocd_app_info{health_status="Degraded"} > 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "ArgoCD Application {{ $labels.name }} is Degraded"
EOF
```

### Step 10: Complete Workflow Test

```bash
# 1. Tạo một thay đổi nhỏ trong code
echo "v2.0.0" > version.txt
git add version.txt
git commit -m "feat: version 2.0.0"
git push origin main

# 2. GitHub Actions sẽ tự động trigger
gh run list --limit 5

# 3. Watch pipeline
gh run watch

# 4. Kiểm tra image đã được push
docker pull ghcr.io/myorg/myapp:main-$(git rev-parse --short HEAD)

# 5. Kiểm tra dev đã được update
argocd app get my-webapp-dev

# 6. Promote lên staging (manual trigger)
gh workflow run promote.yaml --field target_env=staging

# 7. Promote lên prod với canary
kubectl argo rollouts get rollout my-webapp -n production --watch

# 8. Monitor canary metrics
kubectl get analysisrun -n production --watch
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# Verify full pipeline end-to-end
# 1. Check GitHub Actions
gh run list --status success --limit 5

# 2. Check image trong registry
docker manifest inspect ghcr.io/myorg/myapp:latest

# 3. Verify image signature
cosign verify ghcr.io/myorg/myapp:latest \
  --certificate-identity-regexp "https://github.com/myorg/myapp" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"

# 4. Check kustomize renders correctly
kustomize build manifests/overlays/prod/ | kubectl apply --dry-run=client -f -

# 5. Check ArgoCD sync status
argocd app list
argocd app get my-webapp-dev
argocd app get my-webapp-prod

# 6. Check Rollout status
kubectl argo rollouts get rollout my-webapp -n production

# 7. Check pods running latest image
kubectl get pods -n production -o jsonpath='{.items[*].spec.containers[*].image}'

# 8. Smoke test
curl -f https://myapp.example.com/health
curl -f https://myapp.example.com/version
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xóa Argo Rollouts
kubectl argo rollouts abort my-webapp -n production  # Nếu đang rollout
kubectl delete rollout my-webapp -n production
kubectl delete namespace argo-rollouts

# Xóa kustomize deployments
kubectl delete -k manifests/overlays/dev/
kubectl delete -k manifests/overlays/prod/

# Xóa ArgoCD applications
argocd app delete my-webapp-dev --cascade
argocd app delete my-webapp-prod --cascade

# Xóa External Secrets
kubectl delete externalsecret --all -n production
helm uninstall external-secrets -n external-secrets

# Xóa GitHub Actions secrets (nếu cần)
gh secret remove KUBE_CONFIG
gh secret remove ARGOCD_TOKEN
```

---

## 💡 Tips & Gotchas

### ⚠️ Security Best Practices

1. **Không commit secrets vào Git** — dùng Sealed Secrets hoặc External Secrets
2. **Pin action versions** trong GitHub Actions:
   ```yaml
   # BAD
   uses: actions/checkout@v3
   # GOOD
   uses: actions/checkout@692973e3d937129bcbf40652eb9f2f61becf3332  # v4.1.2
   ```
3. **Minimal permissions** cho workflow tokens:
   ```yaml
   permissions:
     contents: read
     packages: write
     id-token: write  # Cho Cosign keyless signing
   ```
4. **Branch protection rules** — require PR reviews cho main/prod

### ⚠️ Kustomize Gotchas

1. **Namespace không tự tạo** — phải khai báo trong namespace resource hoặc dùng `--create-namespace`
2. **Label selector thay đổi** sẽ cần delete + recreate Deployment
3. **`commonLabels` áp dụng cho cả selector** — cẩn thận khi thêm sau

### 💡 Advanced Patterns

1. **Feature flags** kết hợp với Canary:
   ```bash
   # Launch Darkly hoặc Flipt để toggle features
   # Canary: deploy code + disable feature flag
   # Promote: enable feature flag dần dần
   ```

2. **Progressive delivery với Flagger**:
   ```bash
   # Flagger tự động hóa canary analysis
   helm repo add flagger https://flagger.app
   helm install flagger flagger/flagger \
     --set meshProvider=istio \
     --set metricsServer=http://prometheus:9090
   ```

3. **Multi-repo vs Mono-repo GitOps**:
   - **App repo**: source code, Dockerfile, unit tests
   - **Config repo**: Kustomize/Helm values, được cập nhật bởi CI từ app repo
   - ArgoCD theo dõi config repo

---

## 📚 Tham khảo (References)

- [GitHub Actions Docs](https://docs.github.com/en/actions)
- [Kustomize Docs](https://kubectl.docs.kubernetes.io/guides/introduction/kustomize/)
- [Argo Rollouts](https://argoproj.github.io/rollouts/)
- [Cosign/Sigstore](https://docs.sigstore.dev/cosign/overview/)
- [SLSA Framework](https://slsa.dev/)
- [External Secrets Operator](https://external-secrets.io/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [Progressive Delivery](https://www.weave.works/technologies/progressive-delivery/)

---

## 🎓 Hoàn thành Learning Path!

Chúc mừng! Bạn đã hoàn thành toàn bộ **36 labs** của Kubernetes Learning Path!

```
Phase 1 (Labs 01-05):  K8s Fundamentals
Phase 2 (Labs 06-10):  Workloads & Scheduling
Phase 3 (Labs 11-15):  Networking & Services
Phase 4 (Labs 16-20):  Storage & Configuration
Phase 5 (Labs 21-25):  Security & RBAC
Phase 6 (Labs 26-28):  Observability
Phase 7 (Labs 29-32):  Advanced Patterns
Phase 8 (Labs 33-36):  GitOps & CI/CD ← YOU ARE HERE ✅
```

**Các bước tiếp theo:**
- Luyện thi CKA (Certified Kubernetes Administrator)
- Luyện thi CKAD (Certified Kubernetes Application Developer)
- Nghiên cứu CKS (Certified Kubernetes Security Specialist)
- Tham gia CNCF community và đóng góp open source
