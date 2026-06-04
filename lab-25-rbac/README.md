# Lab 25 — RBAC: Role & ClusterRole

## 🎯 Mục tiêu (Objectives)

Sau khi hoàn thành lab này, bạn sẽ:
- Hiểu luồng xác thực (AuthN → AuthZ) trong Kubernetes
- Phân biệt **Users** vs **ServiceAccounts**
- Phân biệt **Role** (namespace-scoped) vs **ClusterRole** (cluster-scoped)
- Tạo và bind các **RoleBinding** / **ClusterRoleBinding**
- Sử dụng `kubectl auth can-i` để kiểm tra quyền
- Impersonate user/serviceaccount để test
- Áp dụng các pattern phổ biến: read-only, developer, admin

---

## 📋 Prerequisites

- Lab 01–24 hoàn thành (cluster đang chạy)
- `kubectl` đã cấu hình với quyền admin
- Hiểu cơ bản về Namespace và Pod

```bash
# Kiểm tra cluster đang chạy
kubectl cluster-info
kubectl get nodes
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Kubernetes Auth Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    API Server Request                        │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
          ┌───────────────────────┐
          │   Authentication      │  ← "Who are you?"
          │   (AuthN)             │
          │   - X.509 Certs       │
          │   - Bearer Tokens     │
          │   - OIDC              │
          └───────────┬───────────┘
                      │ Identity confirmed
                      ▼
          ┌───────────────────────┐
          │   Authorization       │  ← "What can you do?"
          │   (AuthZ / RBAC)      │
          │   - Role              │
          │   - ClusterRole       │
          │   - RoleBinding       │
          │   - ClusterRoleBinding│
          └───────────┬───────────┘
                      │ Allowed?
                      ▼
          ┌───────────────────────┐
          │  Admission Control    │  ← "Is it valid?"
          │  - MutatingWebhook    │
          │  - ValidatingWebhook  │
          └───────────┬───────────┘
                      │
                      ▼
                  etcd / Action
```

### Users vs ServiceAccounts

| Aspect | User | ServiceAccount |
|--------|------|----------------|
| Managed by | External (certs/OIDC) | Kubernetes API |
| Namespace | Cluster-wide | Namespace-scoped |
| Use case | Human operators | Pods/applications |
| Stored in | External | k8s Secret/Token |
| Authenticate via | kubeconfig certs | Mounted token |

### Role vs ClusterRole

```
Namespace: "production"
┌────────────────────────────────────────┐
│  Role "pod-reader"                     │
│  ✅ Only works in "production" ns       │
│  resources: pods                       │
│  verbs: get, list, watch               │
└────────────────────────────────────────┘

Cluster-wide:
┌────────────────────────────────────────┐
│  ClusterRole "node-reader"             │
│  ✅ Works across ALL namespaces         │
│  ✅ Can target cluster-scoped resources │
│  resources: nodes, persistentvolumes   │
│  verbs: get, list, watch               │
└────────────────────────────────────────┘
```

### RBAC Verbs

| Verb | HTTP Method | Description |
|------|------------|-------------|
| `get` | GET | Read a single resource |
| `list` | GET (collection) | List all resources |
| `watch` | GET + watch | Stream changes |
| `create` | POST | Create a resource |
| `update` | PUT | Replace a resource |
| `patch` | PATCH | Partial update |
| `delete` | DELETE | Delete a resource |
| `deletecollection` | DELETE | Delete multiple |

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Tạo Namespace cho Lab

```bash
kubectl create namespace rbac-lab
kubectl create namespace rbac-prod
```

### Step 2: Tạo ServiceAccount

```bash
kubectl apply -f manifests/serviceaccount-app.yaml

# Kiểm tra
kubectl get serviceaccount -n rbac-lab
kubectl describe serviceaccount app-service-account -n rbac-lab
```

### Step 3: Tạo Role Read-Only

```bash
kubectl apply -f manifests/role-readonly.yaml

# Kiểm tra
kubectl get role -n rbac-lab
kubectl describe role pod-reader -n rbac-lab
```

### Step 4: Tạo Role Developer

```bash
kubectl apply -f manifests/role-developer.yaml

# Kiểm tra
kubectl describe role developer -n rbac-lab
```

### Step 5: Tạo RoleBinding

```bash
kubectl apply -f manifests/rolebinding-app.yaml

# Kiểm tra binding
kubectl get rolebinding -n rbac-lab
kubectl describe rolebinding app-pod-reader -n rbac-lab
```

### Step 6: Tạo ClusterRole cho Node Reader

```bash
kubectl apply -f manifests/clusterrole-node-reader.yaml

# Kiểm tra
kubectl get clusterrole node-reader
kubectl describe clusterrole node-reader
```

### Step 7: Tạo ClusterRoleBinding

```bash
kubectl apply -f manifests/clusterrolebinding.yaml

# Kiểm tra
kubectl get clusterrolebinding node-reader-binding
```

### Step 8: Deploy Pod với ServiceAccount

```bash
kubectl apply -f manifests/pod-with-serviceaccount.yaml

# Kiểm tra pod đang chạy
kubectl get pod sa-demo-pod -n rbac-lab
kubectl describe pod sa-demo-pod -n rbac-lab
```

### Step 9: Test quyền với `kubectl auth can-i`

```bash
# Test với ServiceAccount app-service-account
# Format: kubectl auth can-i <verb> <resource> --as=system:serviceaccount:<ns>:<sa> -n <ns>

# ✅ Có thể list pods (được phép)
kubectl auth can-i list pods \
  --as=system:serviceaccount:rbac-lab:app-service-account \
  -n rbac-lab

# ✅ Có thể get pods (được phép)
kubectl auth can-i get pods \
  --as=system:serviceaccount:rbac-lab:app-service-account \
  -n rbac-lab

# ❌ Không thể delete pods (không được phép)
kubectl auth can-i delete pods \
  --as=system:serviceaccount:rbac-lab:app-service-account \
  -n rbac-lab

# ❌ Không thể list deployments (không được phép)
kubectl auth can-i list deployments \
  --as=system:serviceaccount:rbac-lab:app-service-account \
  -n rbac-lab

# ❌ Không thể get nodes (namespace-scoped only)
kubectl auth can-i get nodes \
  --as=system:serviceaccount:rbac-lab:app-service-account
```

### Step 10: Test trong Pod thực tế (exec vào pod)

```bash
# Exec vào pod và test API calls với mounted token
kubectl exec -it sa-demo-pod -n rbac-lab -- /bin/sh

# Bên trong pod:
# Lấy token từ mounted service account
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
APISERVER=https://kubernetes.default.svc

# Test: list pods (should work)
curl -s --cacert $CACERT \
  -H "Authorization: Bearer $TOKEN" \
  $APISERVER/api/v1/namespaces/$NAMESPACE/pods | head -20

# Test: list secrets (should fail)
curl -s --cacert $CACERT \
  -H "Authorization: Bearer $TOKEN" \
  $APISERVER/api/v1/namespaces/$NAMESPACE/secrets

exit
```

### Step 11: Test ClusterRole Node Reader

```bash
# Developer ServiceAccount có thể đọc nodes?
kubectl auth can-i list nodes \
  --as=system:serviceaccount:rbac-lab:app-service-account

# Nếu ClusterRoleBinding gán đúng, kết quả là "yes"
kubectl auth can-i get nodes \
  --as=system:serviceaccount:rbac-lab:app-service-account
```

### Step 12: Tạo User giả lập với Impersonation

```bash
# Impersonate user "alice" (user không tồn tại nhưng để test)
kubectl auth can-i list pods --as=alice -n rbac-lab
# → no (chưa có RBAC cho alice)

# Impersonate với group
kubectl auth can-i list nodes --as=jane --as-group=system:masters
# → yes (system:masters là cluster-admin group)

# Xem tất cả quyền của một service account
kubectl auth can-i --list \
  --as=system:serviceaccount:rbac-lab:app-service-account \
  -n rbac-lab
```

### Step 13: Sử dụng ClusterRole built-in

```bash
# Xem các ClusterRole có sẵn
kubectl get clusterrole | grep -v system:

# Các ClusterRole phổ biến:
# - cluster-admin    : toàn quyền
# - admin            : admin trong namespace
# - edit             : read/write trong namespace
# - view             : read-only trong namespace

# Tạo binding cho "view" ClusterRole trong namespace cụ thể
kubectl create rolebinding view-binding \
  --clusterrole=view \
  --serviceaccount=rbac-lab:app-service-account \
  --namespace=rbac-lab \
  --dry-run=client -o yaml
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# 1. Kiểm tra tất cả RBAC resources
echo "=== ServiceAccounts ==="
kubectl get serviceaccount -n rbac-lab

echo "=== Roles ==="
kubectl get role -n rbac-lab

echo "=== RoleBindings ==="
kubectl get rolebinding -n rbac-lab

echo "=== ClusterRoles (custom) ==="
kubectl get clusterrole | grep -v "^system:"

echo "=== ClusterRoleBindings (custom) ==="
kubectl get clusterrolebinding | grep -v "^system:"

# 2. Verify permissions matrix
SA="system:serviceaccount:rbac-lab:app-service-account"
echo "=== Permission Matrix for $SA ==="
for verb in get list watch create update patch delete; do
  for resource in pods services deployments secrets nodes; do
    result=$(kubectl auth can-i $verb $resource --as=$SA -n rbac-lab 2>/dev/null)
    echo "$verb $resource: $result"
  done
done

# 3. Kiểm tra Pod đang dùng đúng ServiceAccount
kubectl get pod sa-demo-pod -n rbac-lab -o jsonpath='{.spec.serviceAccountName}'
echo ""
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xóa tất cả resources trong lab
kubectl delete -f manifests/ --ignore-not-found=true

# Xóa namespace
kubectl delete namespace rbac-lab rbac-prod --ignore-not-found=true

# Kiểm tra đã xóa hết
kubectl get all -n rbac-lab 2>/dev/null || echo "Namespace đã được xóa"
```

---

## 💡 Tips & Gotchas

### ⚠️ Least Privilege Principle
Luôn cấp quyền tối thiểu cần thiết. Tránh dùng `*` trong resources hoặc verbs:
```yaml
# ❌ BAD - quá rộng
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]

# ✅ GOOD - cụ thể
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
```

### ⚠️ ClusterRole có thể bind vào Namespace
Bạn có thể dùng `RoleBinding` (không phải `ClusterRoleBinding`) để bind một `ClusterRole` vào một namespace cụ thể. Điều này hữu ích để tái sử dụng ClusterRole nhưng giới hạn scope:
```bash
kubectl create rolebinding local-admin \
  --clusterrole=admin \
  --user=alice \
  --namespace=production
```

### ⚠️ ServiceAccount Token Automount
Mặc định token được mount vào tất cả pods. Tắt nếu pod không cần gọi API:
```yaml
spec:
  automountServiceAccountToken: false
```

### ⚠️ Audit RBAC thường xuyên
```bash
# Tìm tất cả bindings với cluster-admin
kubectl get clusterrolebindings -o json | \
  jq '.items[] | select(.roleRef.name == "cluster-admin") | .metadata.name'
```

### 💡 Dùng `kubectl auth can-i --list` để debug
```bash
kubectl auth can-i --list --as=system:serviceaccount:default:default -n default
```

---

## 📚 Tham khảo (References)

- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#command-line-utilities)
- [ServiceAccount Token Projection](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)
- [Auditing](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/)

## 🔗 Next Lab

➡️ **[Lab 26 — Security Context & Pod Security Standards](../lab-26-pod-security/README.md)**
