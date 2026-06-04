# Lab 24 — Custom Resource Definition (CRD) & Operator Pattern

## 🎯 Mục tiêu (Objectives)

Sau lab này, bạn sẽ hiểu và làm được:
- Hiểu tại sao cần mở rộng Kubernetes API với CRDs
- Hiểu anatomy của một CRD (group, version, kind, schema validation)
- Tạo và sử dụng Custom Resources
- Hiểu Operator Pattern và Reconcile Loop
- Biết các Operator nổi tiếng trong ecosystem: cert-manager, prometheus-operator, postgres-operator
- Cài đặt cert-manager như một ví dụ Operator thực tế
- Tạo `Issuer` và `Certificate` resources với cert-manager

---

## 📋 Prerequisites

- Hoàn thành Lab 23
- Hiểu cơ bản về Kubernetes API resources
- Có cluster với quyền admin (để tạo CRDs)

```bash
# Kiểm tra quyền tạo CRDs
kubectl auth can-i create customresourcedefinitions --all-namespaces

# Xem CRDs hiện có
kubectl get crd
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Tại sao cần extend Kubernetes API?

Kubernetes được thiết kế là **extensible**. Thay vì cố gắng có sẵn mọi resource type, K8s cho phép bạn tạo resource types riêng phù hợp với domain của ứng dụng.

```
Built-in Kubernetes Resources:
  Pod, Deployment, Service, ConfigMap, Secret...

Extended Resources (CRDs):
  Certificate (cert-manager)
  PrometheusRule (prometheus-operator)
  PostgresCluster (postgres-operator)
  Website (custom - lab này)
  VirtualService (Istio)
  HelmRelease (Flux CD)
```

### CRD Anatomy

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: websites.example.com      # <plural>.<group>
spec:
  group: example.com              # API group (như apps, networking.k8s.io)
  versions:
  - name: v1alpha1                # Version (v1alpha1, v1beta1, v1)
    served: true                  # API đang được serve
    storage: true                 # Version này được lưu trong etcd
    schema:                       # OpenAPI v3 schema validation
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              url:
                type: string
  scope: Namespaced               # Namespaced hoặc Cluster
  names:
    plural: websites              # kubectl get websites
    singular: website             # kubectl get website
    kind: Website                 # apiVersion: example.com/v1alpha1 kind: Website
    shortNames:                   # kubectl get ws
    - ws
```

### Operator Pattern

```
┌──────────────────────────────────────────────────────────────────┐
│                    Operator Pattern                               │
│                                                                  │
│  CRD định nghĩa "WHAT" (resource type mới)                      │
│  Controller/Operator làm "HOW" (logic để xử lý resource)        │
│                                                                  │
│  ┌─────────────┐  create/update   ┌──────────────────────────┐  │
│  │   User      │─────────────────►│  Custom Resource         │  │
│  │ (kubectl)   │                  │  (instance of CRD)       │  │
│  └─────────────┘                  └──────────────┬───────────┘  │
│                                                  │ watch        │
│                                   ┌──────────────▼───────────┐  │
│                                   │      Controller           │  │
│                                   │   (Reconcile Loop)        │  │
│                                   │                          │  │
│                                   │  Current State ──────►  │  │
│                                   │  Desired State   Reconcile│  │
│                                   │  (from CR spec)          │  │
│                                   └──────────────┬───────────┘  │
│                                                  │ create/manage│
│                                   ┌──────────────▼───────────┐  │
│                                   │  Kubernetes Resources    │  │
│                                   │  (Pods, Services, etc.)  │  │
│                                   └──────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

### Reconcile Loop

```go
// Pseudo-code của Reconcile Loop
func Reconcile(request Request) (Result, error) {
    // 1. Lấy Custom Resource từ API
    website := getWebsite(request.Name)
    
    // 2. So sánh current state vs desired state
    currentDeployment := getDeployment(website.Name)
    
    // 3. Reconcile (làm cho current = desired)
    if currentDeployment == nil {
        createDeployment(website.Spec)  // Tạo mới
    } else if needsUpdate(currentDeployment, website.Spec) {
        updateDeployment(currentDeployment, website.Spec)  // Cập nhật
    }
    
    // 4. Update status
    website.Status.Ready = true
    updateStatus(website)
    
    return Result{}, nil
}
```

### Real-world Operators

| Operator | Quản lý | GitHub |
|----------|---------|--------|
| cert-manager | TLS certificates | jetstack/cert-manager |
| prometheus-operator | Prometheus + Alertmanager | prometheus-operator/prometheus-operator |
| postgres-operator | PostgreSQL clusters | zalando/postgres-operator |
| strimzi | Apache Kafka | strimzi-io/strimzi-kafka-operator |
| flux | GitOps deployments | fluxcd/flux2 |
| argocd | GitOps deployments | argoproj/argo-cd |

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Tạo CRD đầu tiên — Website

```bash
# Tạo CRD
kubectl apply -f manifests/crd-website.yaml

# Kiểm tra CRD đã được tạo
kubectl get crd websites.example.com

# Xem CRD chi tiết
kubectl describe crd websites.example.com

# CRD đã đăng ký vào API Server
kubectl api-resources | grep website
# websites   ws   example.com/v1alpha1   true   Website
```

---

### Step 2: Tạo Custom Resource (instance của CRD)

```bash
# Tạo một Website resource
kubectl apply -f manifests/website-resource.yaml

# Xem websites
kubectl get websites
kubectl get ws    # Dùng shortName

# Xem chi tiết
kubectl describe website my-company-website

# Xem như YAML
kubectl get website my-company-website -o yaml
```

**Expected output:**
```
NAME                   URL                        REPLICAS   AGE
my-company-website     https://example.com        3          10s
blog-website           https://blog.example.com   1          10s
```

---

### Step 3: Tạo CRD BackupPolicy

```bash
# Tạo CRD phức tạp hơn với schema validation
kubectl apply -f manifests/crd-backuppolicy.yaml

# Kiểm tra CRD
kubectl get crd backuppolicies.backup.example.com

# Thử tạo BackupPolicy hợp lệ
kubectl apply -f - <<EOF
apiVersion: backup.example.com/v1alpha1
kind: BackupPolicy
metadata:
  name: daily-backup
spec:
  schedule: "0 2 * * *"       # 2 AM mỗi ngày
  retentionDays: 30
  target:
    type: s3
    bucket: my-backups
    region: us-east-1
  encryption:
    enabled: true
EOF

kubectl get backuppolicies
kubectl describe backuppolicy daily-backup

# Thử tạo BackupPolicy KHÔNG hợp lệ (vi phạm schema)
kubectl apply -f - <<EOF
apiVersion: backup.example.com/v1alpha1
kind: BackupPolicy
metadata:
  name: invalid-backup
spec:
  retentionDays: -5    # Giá trị âm - vi phạm minimum: 1
  target:
    type: invalid-type  # Không nằm trong enum
EOF
# Expected: Error! Validation failed
```

---

### Step 4: Cài đặt cert-manager — Operator thực tế

cert-manager là một trong những Operators phổ biến nhất, quản lý TLS certificates tự động.

```bash
# Cài cert-manager bằng kubectl
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml

# Chờ cert-manager pods sẵn sàng
kubectl -n cert-manager rollout status deployment/cert-manager
kubectl -n cert-manager rollout status deployment/cert-manager-webhook
kubectl -n cert-manager rollout status deployment/cert-manager-cainjector

# Kiểm tra pods
kubectl -n cert-manager get pods
```

**Expected output:**
```
NAME                                      READY   STATUS    RESTARTS   AGE
cert-manager-7f9f8648d9-xkj2p             1/1     Running   0          2m
cert-manager-cainjector-bd5f9c764-np2q1   1/1     Running   0          2m
cert-manager-webhook-7c9d4b7f8-kr3m2      1/1     Running   0          2m
```

```bash
# Xem CRDs được cài bởi cert-manager
kubectl get crd | grep cert-manager.io
# certificates.cert-manager.io
# certificaterequests.cert-manager.io
# challenges.acme.cert-manager.io
# clusterissuers.cert-manager.io
# issuers.cert-manager.io
# orders.acme.cert-manager.io
```

---

### Step 5: Sử dụng cert-manager — Tạo self-signed Certificate

```bash
# Tạo ClusterIssuer dùng self-signed CA
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF

kubectl get clusterissuer selfsigned-issuer
# READY phải là True

# Tạo Certificate resource
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-tls-cert
  namespace: default
spec:
  secretName: example-tls-secret   # cert-manager sẽ tạo Secret này
  duration: 2160h                   # 90 days
  renewBefore: 360h                 # Renew 15 days trước khi hết hạn
  subject:
    organizations:
    - Example Corp
  dnsNames:
  - example.com
  - www.example.com
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
EOF

# Theo dõi certificate được issue
kubectl get certificate example-tls-cert -w

# Xem chi tiết
kubectl describe certificate example-tls-cert

# Xem Secret được tạo tự động bởi cert-manager
kubectl get secret example-tls-secret
kubectl describe secret example-tls-secret
```

**Expected output:**
```
NAME               READY   SECRET               AGE
example-tls-cert   True    example-tls-secret   30s
```

```bash
# Xem nội dung certificate
kubectl get secret example-tls-secret -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout | grep -E "Subject:|DNS:|Not "
```

---

### Step 6: Hiểu Reconcile Loop qua cert-manager

```bash
# Xem cert-manager logs để hiểu reconcile loop
kubectl -n cert-manager logs -l app=cert-manager --tail=20 | grep -i "reconcil\|certif"

# Xem events của Certificate
kubectl get events --sort-by='.lastTimestamp' | grep -i "certif\|issue"

# Simulate reconciliation: xóa Secret → cert-manager tự tạo lại!
kubectl delete secret example-tls-secret

# Cert-manager sẽ detect Secret bị mất và tự tạo lại
kubectl get secret example-tls-secret -w
# Secret xuất hiện lại trong vài giây!

# Đây chính là sức mạnh của Reconcile Loop:
# Controller liên tục đảm bảo "actual state" = "desired state"
```

---

### Step 7: Khám phá Operator Resources

```bash
# Xem tất cả CRDs trong cluster
kubectl get crd

# Xem các API groups mới được thêm bởi Operators
kubectl api-versions | grep -v "^v\|k8s.io\|kubernetes"

# Xem API resources của cert-manager
kubectl api-resources --api-group=cert-manager.io

# Xem cert-manager CRD schema
kubectl get crd certificates.cert-manager.io -o jsonpath='{.spec.versions[0].schema.openAPIV3Schema}' | python3 -m json.tool | head -50
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# 1. Kiểm tra CRDs đã tạo
kubectl get crd | grep -E "example.com|backup.example"

# 2. Kiểm tra Custom Resources
kubectl get websites
kubectl get backuppolicies

# 3. Kiểm tra cert-manager hoạt động
kubectl -n cert-manager get pods

# 4. Kiểm tra Certificate được issued
kubectl get certificate example-tls-cert
# READY phải là True

# 5. Kiểm tra Secret được tạo
kubectl get secret example-tls-secret

# 6. Kiểm tra cert-manager CRDs
kubectl get crd | grep cert-manager | wc -l
# Nên có ít nhất 6 CRDs

# 7. Test schema validation
kubectl apply -f - <<EOF 2>&1 | grep -i "error\|invalid"
apiVersion: example.com/v1alpha1
kind: Website
metadata:
  name: test-invalid
spec:
  replicas: -1
EOF
# Expected: Error về validation
```

**Checklist:**
- [ ] CRD `websites.example.com` tồn tại
- [ ] Có thể tạo và get Website resources
- [ ] Schema validation hoạt động (từ chối invalid data)
- [ ] cert-manager Pods đang Running
- [ ] Certificate `READY=True` và Secret đã được tạo
- [ ] Khi xóa Secret, cert-manager tự tạo lại

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xóa cert-manager resources
kubectl delete certificate example-tls-cert --ignore-not-found
kubectl delete clusterissuer selfsigned-issuer --ignore-not-found
kubectl delete secret example-tls-secret --ignore-not-found

# Xóa custom resources
kubectl delete websites --all --ignore-not-found
kubectl delete backuppolicies --all --ignore-not-found

# Xóa CRDs (cẩn thận: xóa CRD sẽ xóa TẤT CẢ instances)
kubectl delete -f manifests/crd-website.yaml --ignore-not-found
kubectl delete -f manifests/crd-backuppolicy.yaml --ignore-not-found

# Xóa cert-manager (nếu không cần nữa)
kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml --ignore-not-found

# Kiểm tra đã sạch
kubectl get crd | grep example.com
kubectl get pods -n cert-manager
```

---

## 💡 Tips & Gotchas

### ⚠️ Thường gặp

1. **Xóa CRD xóa luôn tất cả instances**
   ```bash
   # CẢNH BÁO: Trước khi xóa CRD, backup tất cả instances
   kubectl get websites -A -o yaml > websites-backup.yaml
   kubectl delete crd websites.example.com
   # Tất cả Website resources sẽ bị xóa theo!
   ```

2. **CRD schema validation từ chối resource**
   ```bash
   # Kiểm tra schema của CRD
   kubectl get crd <name> -o jsonpath='{.spec.versions[0].schema}' | python3 -m json.tool
   # Sửa resource theo đúng schema
   ```

3. **cert-manager webhook không sẵn sàng**
   ```bash
   kubectl -n cert-manager get pods
   kubectl -n cert-manager logs -l app=cert-manager-webhook
   # Thường do timing issue khi mới cài — chờ 1-2 phút
   ```

4. **CRD version migration**
   ```bash
   # Khi upgrade CRD từ v1alpha1 → v1, cần conversion webhook
   # Hoặc dùng storage version migration
   # Tham khảo: https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definition-versioning/
   ```

### 💡 Best Practices

- **Schema validation** là bắt buộc cho production CRDs — tránh garbage data trong etcd
- Luôn define **`status` subresource** trong CRD để tách biệt spec và status updates
- Dùng **`additionalPrinterColumns`** để hiện thông tin hữu ích khi `kubectl get`
- Khi viết Operator, implement **idempotent reconcile loop** — gọi nhiều lần phải cho cùng kết quả
- Operator framework phổ biến: **Kubebuilder** (Go), **Operator SDK** (Go/Helm/Ansible)
- Theo dõi **OperatorHub.io** để xem Operators cộng đồng trước khi viết mới

---

## 🚀 Bonus: Tạo simple Operator bằng shell script

Mặc dù production Operators thường viết bằng Go với Kubebuilder, đây là demo concept:

```bash
# Simple reconcile loop bằng shell (concept demonstration)
while true; do
  # Get desired state từ Custom Resources
  WEBSITES=$(kubectl get websites -o jsonpath='{.items[*].metadata.name}')
  
  for WEBSITE in $WEBSITES; do
    REPLICAS=$(kubectl get website $WEBSITE -o jsonpath='{.spec.replicas}')
    URL=$(kubectl get website $WEBSITE -o jsonpath='{.spec.url}')
    
    # Check if Deployment exists
    if ! kubectl get deployment $WEBSITE &>/dev/null; then
      echo "Creating deployment for Website: $WEBSITE"
      kubectl create deployment $WEBSITE --image=nginx --replicas=$REPLICAS
    fi
    
    # Reconcile replicas
    CURRENT=$(kubectl get deployment $WEBSITE -o jsonpath='{.spec.replicas}')
    if [ "$CURRENT" != "$REPLICAS" ]; then
      echo "Updating replicas for $WEBSITE: $CURRENT → $REPLICAS"
      kubectl scale deployment $WEBSITE --replicas=$REPLICAS
    fi
  done
  
  sleep 15  # Reconcile every 15 seconds
done
```

---

## 📚 Tham khảo (References)

- [Custom Resources Documentation](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/)
- [CRD Versioning](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definition-versioning/)
- [Operator Pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)
- [Kubebuilder Book](https://book.kubebuilder.io/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [OperatorHub.io](https://operatorhub.io/)
- [CNCF Operator White Paper](https://github.com/cncf/tag-app-delivery/blob/main/operator-wg/whitepaper/Operator-WhitePaper_v1-0.md)

---

## 🎉 Hoàn thành Phase 5!

Bạn đã hoàn thành **Phase 5: Advanced Kubernetes Features**:

| Lab | Chủ đề | Kỹ năng |
|-----|--------|---------|
| Lab 20 | HPA | Horizontal scaling tự động theo CPU/Memory |
| Lab 21 | VPA | Vertical scaling tự động resource requests |
| Lab 22 | Scheduling | Taints, Tolerations, Node/Pod Affinity |
| Lab 23 | PDB | Bảo vệ ứng dụng khỏi disruptions |
| Lab 24 | CRD & Operator | Extend Kubernetes API |

### 🔗 Tiếp theo — Phase 6

- **Lab 25** — Helm Package Manager (Charts, Values, Releases)
- **Lab 26** — Kubernetes RBAC (ServiceAccounts, Roles, ClusterRoles)
- **Lab 27** — Network Policies (micro-segmentation)
- **Lab 28** — Monitoring với Prometheus & Grafana
- **Lab 29** — Logging với EFK Stack
- **Lab 30** — Kubernetes in Production (CI/CD, GitOps với ArgoCD)
