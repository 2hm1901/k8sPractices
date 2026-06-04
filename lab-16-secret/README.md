# Lab 16 — Secret

## 🎯 Mục tiêu (Objectives)

Sau khi hoàn thành lab này, bạn sẽ có thể:

- Hiểu các loại Secret trong Kubernetes và khi nào dùng loại nào
- Hiểu **base64 encoding ≠ encryption** và tại sao cần Encryption at Rest
- Tạo Secret từ literal, file, và YAML manifest
- Inject Secret vào Pod dưới dạng env var và volume
- Cấu hình `imagePullSecrets` để pull image từ private registry
- Hiểu khái niệm Sealed Secrets cho GitOps

---

## 📋 Prerequisites

- Đã hoàn thành Lab 15 (ConfigMap)
- `kubectl` đã cấu hình kết nối tới cluster
- `base64` command available (có sẵn trên Linux/macOS)
- Optional: Docker Hub account để test imagePullSecrets

```bash
kubectl cluster-info
echo "Test base64" | base64
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Secret vs ConfigMap

| Tiêu chí | ConfigMap | Secret |
|---|---|---|
| Mục đích | Non-sensitive config | Sensitive data |
| Encoding | Plain text | Base64 encoded |
| Storage | etcd (plain) | etcd (có thể encrypt) |
| Memory | Disk | tmpfs (in-memory) |
| RBAC | Standard | Tách biệt hơn |

### Các loại Secret

```
kubernetes.io/
├── Opaque                  → Generic key-value (default)
├── service-account-token   → SA token (auto-created)
├── dockerconfigjson        → Docker registry credentials
├── dockercfg               → Legacy docker config
├── basic-auth              → Username/password
├── ssh-auth                → SSH private key
├── tls                     → TLS certificate & key
└── bootstrap.kubernetes.io/token → Bootstrap token
```

### ⚠️ Base64 KHÔNG phải Encryption!

```bash
# Base64 encoding - bất kỳ ai cũng decode được
echo -n "my-super-secret-password" | base64
# bXktc3VwZXItc2VjcmV0LXBhc3N3b3Jk

# Decode ngược lại trivially
echo "bXktc3VwZXItc2VjcmV0LXBhc3N3b3Jk" | base64 --decode
# my-super-secret-password
```

**Encryption at Rest**: Cần bật `EncryptionConfiguration` trong API server để mã hóa thật sự data trong etcd.

---

## 🛠️ Thực hành (Hands-on)

### Bước 1: Tạo Namespace

```bash
kubectl create namespace lab16
kubectl config set-context --current --namespace=lab16
```

### Bước 2: Hiểu Base64 Encoding

```bash
# Encode
echo -n "admin" | base64
# YWRtaW4=

echo -n "P@ssw0rd123!" | base64
# UEBzc3cwcmQxMjMh

# QUAN TRỌNG: dùng -n để không encode newline
echo "admin" | base64    # Sai (có \n)
echo -n "admin" | base64 # Đúng

# Decode
echo "YWRtaW4=" | base64 --decode
# admin
```

### Bước 3: Tạo Opaque Secret từ literal

```bash
# Cách 1: kubectl create secret - Kubernetes tự base64 encode
kubectl create secret generic app-credentials \
  --from-literal=DB_USER=admin \
  --from-literal=DB_PASSWORD='P@ssw0rd123!' \
  --from-literal=API_KEY=sk-1234567890abcdef \
  -n lab16

# Xem Secret (values được base64 encoded)
kubectl get secret app-credentials -n lab16 -o yaml
```

Expected output:
```yaml
apiVersion: v1
data:
  API_KEY: c2stMTIzNDU2Nzg5MGFiY2RlZg==
  DB_PASSWORD: UEBzc3cwcmQxMjMh
  DB_USER: YWRtaW4=
kind: Secret
metadata:
  name: app-credentials
  namespace: lab16
type: Opaque
```

```bash
# Decode để verify
kubectl get secret app-credentials -n lab16 \
  -o jsonpath='{.data.DB_PASSWORD}' | base64 --decode
# P@ssw0rd123!

# Describe (không hiện values)
kubectl describe secret app-credentials -n lab16
```

### Bước 4: Tạo Secret từ file

```bash
# Tạo TLS certificate (self-signed cho lab)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/tls.key \
  -out /tmp/tls.crt \
  -subj "/CN=myapp.example.com/O=MyOrg"

# Tạo TLS Secret
kubectl create secret tls myapp-tls \
  --cert=/tmp/tls.crt \
  --key=/tmp/tls.key \
  -n lab16

# Kiểm tra
kubectl describe secret myapp-tls -n lab16
```

```bash
# Tạo secret từ file thông thường
echo -n "my-api-token-value" > /tmp/api-token.txt
kubectl create secret generic api-token \
  --from-file=token=/tmp/api-token.txt \
  -n lab16
```

### Bước 5: Apply Secret từ YAML manifest

```bash
# Apply từ file (đã có base64 values)
kubectl apply -f manifests/secret-app-credentials.yaml
kubectl apply -f manifests/secret-tls.yaml
```

### Bước 6: Inject Secret vào Pod - Env Variables

```bash
kubectl apply -f manifests/pod-with-secret-env.yaml

# Chờ Pod running
kubectl wait --for=condition=Ready pod/pod-secret-env -n lab16 --timeout=60s

# Kiểm tra env vars (values được decode tự động)
kubectl exec pod-secret-env -n lab16 -- env | grep -E "DB_|API_"
```

Expected:
```
DB_USER=admin
DB_PASSWORD=P@ssw0rd123!
API_KEY=sk-1234567890abcdef
```

### Bước 7: Mount Secret như Volume

```bash
kubectl apply -f manifests/pod-with-secret-volume.yaml

kubectl wait --for=condition=Ready pod/pod-secret-volume -n lab16 --timeout=60s

# Kiểm tra files được mount (decoded tự động)
kubectl exec pod-secret-volume -n lab16 -- ls -la /etc/secrets/
kubectl exec pod-secret-volume -n lab16 -- cat /etc/secrets/DB_USER
# admin

# TLS certs mounted
kubectl exec pod-secret-volume -n lab16 -- ls -la /etc/tls/
kubectl exec pod-secret-volume -n lab16 -- cat /etc/tls/tls.crt | head -5

# Secret volume được mount dạng tmpfs (in-memory, không ghi disk)
kubectl exec pod-secret-volume -n lab16 -- mount | grep secrets
# tmpfs on /etc/secrets type tmpfs (ro,relatime)
```

### Bước 8: imagePullSecrets - Private Registry

```bash
# Tạo Docker registry secret
# Thay thế bằng credentials thực của bạn
kubectl create secret docker-registry regcred \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=YOUR_DOCKERHUB_USERNAME \
  --docker-password=YOUR_DOCKERHUB_PASSWORD \
  --docker-email=YOUR_EMAIL \
  -n lab16

# Xem cấu trúc (base64 của JSON credentials)
kubectl get secret regcred -n lab16 -o jsonpath='{.data.\.dockerconfigjson}' \
  | base64 --decode | python3 -m json.tool
```

```yaml
# Sử dụng trong Pod
spec:
  imagePullSecrets:
  - name: regcred
  containers:
  - name: private-app
    image: your-private-registry/your-image:tag
```

```bash
# Apply Deployment với imagePullSecrets
kubectl apply -f manifests/deployment-with-image-pull-secret.yaml
```

### Bước 9: Basic Auth Secret

```bash
# Tạo basic-auth secret
kubectl create secret generic basic-auth \
  --type=kubernetes.io/basic-auth \
  --from-literal=username=admin \
  --from-literal=password=admin123 \
  -n lab16

kubectl describe secret basic-auth -n lab16
```

### Bước 10: SSH Auth Secret

```bash
# Tạo SSH key pair
ssh-keygen -t rsa -b 4096 -f /tmp/ssh-key -N ""

# Tạo SSH auth secret
kubectl create secret generic ssh-key-secret \
  --type=kubernetes.io/ssh-auth \
  --from-file=ssh-privatekey=/tmp/ssh-key \
  -n lab16

kubectl describe secret ssh-key-secret -n lab16
```

### Bước 11: Encryption at Rest (Concept)

```bash
# Kiểm tra data trong etcd (KHÔNG encrypt mặc định)
# Trong môi trường production, cần EncryptionConfiguration

# Ví dụ EncryptionConfiguration (chỉ demo, không apply)
cat << 'EOF'
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: <base64-encoded-32-byte-key>
  - identity: {}  # fallback: no encryption
EOF
```

### Bước 12: Sealed Secrets - Introduction

**Sealed Secrets** (by Bitnami) cho phép encrypt Secret để lưu vào Git repository an toàn.

```bash
# Cài kubeseal CLI
brew install kubeseal  # macOS

# Cài Sealed Secrets controller vào cluster
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Tạo SealedSecret từ Secret
kubectl create secret generic my-secret \
  --from-literal=password=mysecret \
  --dry-run=client -o yaml | \
  kubeseal --format yaml > sealed-secret.yaml

# sealed-secret.yaml an toàn để commit vào Git!
# Chỉ cluster có private key mới decrypt được

cat sealed-secret.yaml
# encryptedData.password = <encrypted gibberish>
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# 1. Liệt kê tất cả Secrets
kubectl get secrets -n lab16

# 2. Verify encoding/decoding
kubectl get secret app-credentials -n lab16 \
  -o jsonpath='{.data.DB_USER}' | base64 --decode
# admin

# 3. Verify env vars trong Pod
kubectl exec pod-secret-env -n lab16 -- printenv DB_PASSWORD
# P@ssw0rd123!

# 4. Verify volume mount là tmpfs
kubectl exec pod-secret-volume -n lab16 -- \
  df -h /etc/secrets
# tmpfs           ... /etc/secrets

# 5. Verify file permissions (default: 0644)
kubectl exec pod-secret-volume -n lab16 -- \
  ls -la /etc/secrets/
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xóa namespace và tất cả resources
kubectl delete namespace lab16

# Xóa files tạm
rm -f /tmp/tls.key /tmp/tls.crt /tmp/api-token.txt
rm -f /tmp/ssh-key /tmp/ssh-key.pub

# Reset namespace context
kubectl config set-context --current --namespace=default
```

---

## 💡 Tips & Gotchas

### ❌ Lỗi thường gặp

1. **Quên dấu `-n` khi base64 encode → newline bị include**
   ```bash
   # Sai:
   echo "mypassword" | base64  # → bXlwYXNzd29yZAo= (có \n)
   
   # Đúng:
   echo -n "mypassword" | base64  # → bXlwYXNzd29yZA==
   ```

2. **Secret không tồn tại khi Pod start**
   ```
   Error: secret "my-secret" not found
   ```
   → Tạo Secret trước khi apply Pod/Deployment

3. **envFrom override env**
   Nếu dùng cả `envFrom` và `env`, `env` sẽ override các key trùng tên.

4. **RBAC và Secrets**
   ```bash
   # Giới hạn ai có thể đọc Secrets
   kubectl create role secret-reader \
     --verb=get,list \
     --resource=secrets \
     --resource-name=app-credentials
   ```

### ✅ Best Practices

- **KHÔNG commit Secret YAML (plain) vào Git** - dùng Sealed Secrets hoặc External Secrets Operator
- Bật **Encryption at Rest** trong production
- Dùng **RBAC** để giới hạn access to Secrets
- Rotate Secrets định kỳ
- Dùng **External Secrets Operator** tích hợp với Vault, AWS SSM, GCP Secret Manager
- Đặt `defaultMode: 0400` cho Secret volumes (chỉ owner đọc được)

```yaml
volumes:
- name: secret-vol
  secret:
    secretName: app-credentials
    defaultMode: 0400  # r--------
```

---

## 📚 Tham khảo (References)

- [Official Docs: Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Secret Types](https://kubernetes.io/docs/concepts/configuration/secret/#secret-types)
- [Encryption at Rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [External Secrets Operator](https://external-secrets.io/)

---

## 🔗 Next Lab

➡️ **[Lab 17 — PersistentVolume & PVC](../lab-17-persistent-volume/README.md)**: Lưu trữ dữ liệu bền vững với Persistent Volumes và PersistentVolumeClaims.
