# Lab 28 — External Secret Management

## 🎯 Mục tiêu

Sau lab này bạn sẽ:
- Hiểu **vấn đề bảo mật** của K8s Secret mặc định (base64 ≠ encryption)
- Cấu hình **Encryption at Rest** cho etcd
- Sử dụng **Sealed Secrets** để GitOps-safe secret management
- Hiểu **External Secrets Operator** tích hợp với Vault / AWS / GCP

## 📋 Prerequisites

- Hoàn thành Lab 16 (Secrets)
- Hoàn thành Lab 25 (RBAC)
- Cluster đang chạy

## 🧠 Lý thuyết nhanh

### Vấn đề với K8s Secret mặc định

```
# Secret "bí mật" chỉ là base64 encode, ai có quyền đọc etcd là lấy được!
kubectl get secret my-secret -o jsonpath='{.data.password}' | base64 -d
# → mysecretpassword123  ← EXPOSED!
```

### Giải pháp

```
┌──────────────────────────────────────────────────────┐
│                   Secret Solutions                    │
│                                                      │
│  1. Encryption at Rest (etcd level)                  │
│     K8s built-in, encrypt data in etcd              │
│                                                      │
│  2. Sealed Secrets (Bitnami)                         │
│     Encrypt with public key → safe to commit to Git │
│     Only cluster can decrypt                         │
│                                                      │
│  3. External Secrets Operator                        │
│     Pull secrets from Vault/AWS/GCP at runtime      │
│     Never store secret value in cluster             │
│                                                      │
│  4. HashiCorp Vault Agent Injector                   │
│     Inject secrets as files/env at pod startup      │
└──────────────────────────────────────────────────────┘
```

## 🛠️ Thực hành

### Step 1: Confirm Secret không được encrypt

```bash
# Kiểm tra etcd secret raw (trên minikube)
kubectl get secret -n default -o yaml | grep -A5 "type: Opaque"

# Xem base64 decoded value (không cần key gì!)
kubectl create secret generic test-secret --from-literal=password=supersecret123
kubectl get secret test-secret -o jsonpath='{.data.password}' | base64 -d
# Output: supersecret123  ← không có gì bảo vệ ngoài RBAC
```

### Step 2: Cài Sealed Secrets

```bash
# Cài Sealed Secrets controller
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --version 2.13.0

# Cài kubeseal CLI
# macOS:
brew install kubeseal

# Verify
kubectl get pods -n kube-system | grep sealed-secrets
```

### Step 3: Tạo Sealed Secret

```bash
# Tạo secret thông thường (chưa apply vào cluster)
kubectl create secret generic my-db-secret \
  --from-literal=username=admin \
  --from-literal=password=supersecret123 \
  --dry-run=client -o yaml > /tmp/my-secret.yaml

# Encrypt thành SealedSecret (an toàn để commit lên Git!)
kubeseal --format yaml < /tmp/my-secret.yaml > manifests/sealed-secret-example.yaml
cat manifests/sealed-secret-example.yaml
# → Thấy encrypted values, không đọc được bằng mắt thường

# Apply SealedSecret vào cluster (controller sẽ decrypt và tạo Secret thật)
kubectl apply -f manifests/sealed-secret-example.yaml
kubectl get secret my-db-secret -o jsonpath='{.data.password}' | base64 -d
```

### Step 4: External Secrets Operator (ESO)

```bash
# Cài External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets \
  external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace

# Verify CRDs installed
kubectl get crd | grep external-secrets
# externalsecrets.external-secrets.io
# secretstores.external-secrets.io
# clustersecretstores.external-secrets.io
```

### Step 5: Cấu hình SecretStore (dùng Fake provider để test)

```bash
kubectl apply -f manifests/external-secret-store.yaml
kubectl apply -f manifests/external-secret.yaml

# Xem ESO tự động tạo K8s Secret từ external store
kubectl get externalsecret
kubectl get secret external-pulled-secret
```

### Step 6: Giới thiệu HashiCorp Vault (conceptual)

```bash
# Install Vault (dev mode cho lab)
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault \
  --namespace vault \
  --create-namespace \
  --set "server.dev.enabled=true"

# Truy cập Vault UI
kubectl port-forward svc/vault 8200:8200 -n vault
# → Open http://localhost:8200 (token: root)

# Lưu secret vào Vault
kubectl exec -n vault vault-0 -- vault kv put secret/myapp \
  username=admin \
  password=vaultpassword

# Đọc từ Vault
kubectl exec -n vault vault-0 -- vault kv get secret/myapp
```

## ✅ Kiểm tra kết quả

```bash
# Sealed Secrets hoạt động
kubectl get sealedsecret
kubectl get secret my-db-secret

# ESO hoạt động
kubectl get secretstore
kubectl get externalsecret
kubectl describe externalsecret external-db-secret | grep "Status"

# Secret được sync
kubectl get secret external-pulled-secret -o jsonpath='{.data}' | base64 -d
```

## 🧹 Dọn dẹp

```bash
kubectl delete -f manifests/
helm uninstall sealed-secrets -n kube-system
helm uninstall external-secrets -n external-secrets
helm uninstall vault -n vault
```

## 💡 Tips & Gotchas

- **Gotcha**: SealedSecret được encrypt cho **một cluster cụ thể** — không copy sang cluster khác được (trừ khi share certificate)
- **Tip**: Dùng `--scope cluster-wide` để SealedSecret hoạt động ở mọi namespace
- **Best practice**: Không bao giờ commit K8s Secret YAML lên Git — chỉ commit SealedSecret
- **Tip**: ESO rotation: set `refreshInterval: 1h` để tự động pull secret mới từ external store
- **Security**: Ngay cả với Sealed Secrets, cần bảo vệ private key của controller (backup và restrict access)

## 📚 Tham khảo

- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [External Secrets Operator](https://external-secrets.io/)
- [Kubernetes Encryption at Rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)
- [HashiCorp Vault on K8s](https://developer.hashicorp.com/vault/docs/platform/k8s)

## 🔗 Next Lab

➡️ [Lab 29 — Logging with EFK Stack](../lab-29-logging-efk/README.md)
