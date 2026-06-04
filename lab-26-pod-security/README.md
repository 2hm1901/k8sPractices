# Lab 26 — Security Context & Pod Security Standards

## 🎯 Mục tiêu (Objectives)

Sau khi hoàn thành lab này, bạn sẽ:
- Cấu hình **Container SecurityContext**: `runAsUser`, `runAsGroup`, `runAsNonRoot`, `readOnlyRootFilesystem`, `allowPrivilegeEscalation`
- Cấu hình **Pod SecurityContext**: `fsGroup`, `sysctls`, `seccompProfile`
- Hiểu Linux Capabilities: tại sao cần `drop ALL` rồi mới `add` cụ thể
- Phân biệt 3 **Pod Security Standards (PSS)**: Privileged / Baseline / Restricted
- Cấu hình **Pod Security Admission** bằng namespace labels
- Hiểu tổng quan về **Seccomp profiles**

---

## 📋 Prerequisites

- Lab 25 (RBAC) hoàn thành
- `kubectl` với quyền admin
- Hiểu cơ bản về Linux users/permissions

```bash
kubectl cluster-info
kubectl get nodes
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Security Context Hierarchy

```
┌─────────────────────────────────────────────────────────────┐
│  Pod Spec                                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Pod SecurityContext (áp dụng cho ALL containers)   │   │
│  │  - runAsUser / runAsGroup                           │   │
│  │  - fsGroup (cho volume mounts)                      │   │
│  │  - sysctls                                          │   │
│  │  - seccompProfile                                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────┐  ┌──────────────────┐                │
│  │ Container A      │  │ Container B      │                │
│  │ SecurityContext  │  │ SecurityContext  │                │
│  │ (override Pod)   │  │ (override Pod)   │                │
│  │ - runAsUser      │  │ - runAsNonRoot   │                │
│  │ - capabilities   │  │ - readOnlyRootFs │                │
│  │ - allowPrivEsc   │  │                  │                │
│  └──────────────────┘  └──────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

### Tại sao cần `drop ALL` rồi `add` cụ thể?

```
Default container capabilities (nguy hiểm!):
  CAP_CHOWN        - Thay đổi file ownership
  CAP_DAC_OVERRIDE - Bypass file read/write permissions
  CAP_NET_BIND_SERVICE - Bind port < 1024
  CAP_NET_RAW      - Raw network sockets (packet sniffing!)
  CAP_SETUID       - Thay đổi UID (leo thang đặc quyền!)
  CAP_SETGID       - Thay đổi GID
  ... và nhiều hơn nữa

Nguyên tắc: Drop ALL, sau đó chỉ add những gì thực sự cần:
  ✅ CAP_NET_BIND_SERVICE  — nếu cần bind port 80/443
  ✅ CAP_SYS_TIME          — nếu cần sync time (NTP)
  ❌ CAP_SYS_ADMIN         — quá nguy hiểm, thường không cần
```

### Pod Security Standards (PSS)

```
┌─────────────────────────────────────────────────────────────┐
│  PRIVILEGED (Không giới hạn)                                │
│  - Cho phép mọi thứ                                         │
│  - Chỉ dùng cho system components (node agents, CNI, CSI)   │
│  - KHÔNG dùng cho application workloads                     │
├─────────────────────────────────────────────────────────────┤
│  BASELINE (Giới hạn cơ bản)                                 │
│  - Ngăn chặn leo thang đặc quyền rõ ràng                    │
│  - Cho phép hầu hết workloads thông thường                  │
│  - Tốt cho: legacy applications, workloads không quá nhạy   │
├─────────────────────────────────────────────────────────────┤
│  RESTRICTED (Hạn chế tối đa)                                │
│  - Theo best practices cứng nhắc nhất                       │
│  - runAsNonRoot, drop ALL capabilities, readOnlyRootFS       │
│  - Tốt cho: production workloads mới, security-critical apps │
└─────────────────────────────────────────────────────────────┘
```

### PSS Namespace Labels

```yaml
# Mode: enforce (reject violating pods)
# Mode: audit   (log violations, allow pods)
# Mode: warn    (warn violations, allow pods)

pod-security.kubernetes.io/enforce: restricted
pod-security.kubernetes.io/enforce-version: latest
pod-security.kubernetes.io/warn: restricted
pod-security.kubernetes.io/audit: restricted
```

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Tạo Namespaces

```bash
# Namespace thông thường (không có PSS)
kubectl create namespace security-lab

# Namespace với PSS Restricted enforcement
kubectl apply -f manifests/namespace-restricted.yaml

# Kiểm tra labels
kubectl get namespace security-lab -o yaml
kubectl get namespace restricted-ns -o yaml | grep pod-security
```

### Step 2: Deploy Pod với Full Security Context (Restricted Profile)

```bash
kubectl apply -f manifests/pod-restricted-security.yaml -n security-lab

# Kiểm tra pod đang chạy
kubectl get pod secure-pod -n security-lab
kubectl describe pod secure-pod -n security-lab

# Verify security context được áp dụng
kubectl exec -n security-lab secure-pod -- id
# Output: uid=1000(nonroot) gid=3000 groups=3000,2000

kubectl exec -n security-lab secure-pod -- whoami
# Output: nonroot (hoặc số UID)
```

### Step 3: Test Read-Only Root Filesystem

```bash
# Thử ghi vào root filesystem (sẽ thất bại)
kubectl exec -n security-lab secure-pod -- touch /test-file
# Output: touch: /test-file: Read-only file system ✅ (bị chặn đúng)

# Nhưng có thể ghi vào tmpfs volume
kubectl exec -n security-lab secure-pod -- touch /tmp/test-file
# Output: (thành công — /tmp là tmpfs)

# Kiểm tra mount points
kubectl exec -n security-lab secure-pod -- mount | grep tmpfs
```

### Step 4: Test Non-Root Enforcement

```bash
# Kiểm tra process đang chạy với đúng UID
kubectl exec -n security-lab secure-pod -- ps aux
# Output: UID column phải là 1000, không phải 0

# Thử chạy command với root (sẽ thất bại vì runAsNonRoot: true)
# Pod sẽ không start nếu container image chạy với UID 0
```

### Step 5: Test Drop Capabilities

```bash
kubectl apply -f manifests/pod-drop-capabilities.yaml -n security-lab

# Kiểm tra capabilities
kubectl exec -n security-lab drop-cap-pod -- cat /proc/1/status | grep Cap
# CapInh: 0000000000000000  (no inherited capabilities)
# CapPrm: 0000000000000000  (no permitted capabilities)
# CapEff: 0000000000000000  (no effective capabilities)

# Thử ping (cần CAP_NET_RAW — bị drop)
kubectl exec -n security-lab drop-cap-pod -- ping -c1 8.8.8.8 2>&1 || true
# Output: ping: permission denied (operation not permitted) ✅
```

### Step 6: Test Seccomp Profile

```bash
kubectl apply -f manifests/pod-seccomp.yaml -n security-lab

# Kiểm tra pod đang chạy
kubectl get pod seccomp-pod -n security-lab

# Seccomp RuntimeDefault chặn các syscalls nguy hiểm:
kubectl exec -n security-lab seccomp-pod -- \
  sh -c 'echo "Seccomp pod is running safely"'
```

### Step 7: Test Pod Security Standards Enforcement

```bash
# Apply namespace với PSS Restricted
kubectl apply -f manifests/namespace-restricted.yaml

# Thử deploy một pod vi phạm PSS Restricted (sẽ bị reject)
kubectl apply -f manifests/pod-violation-test.yaml -n restricted-ns
# Expected output:
# Error from server (Forbidden): pods "violation-pod" is forbidden:
# violates PodSecurity "restricted:latest": ...

# Thử deploy một pod hợp lệ
kubectl apply -f manifests/pod-restricted-security.yaml -n restricted-ns
kubectl get pod secure-pod -n restricted-ns
```

### Step 8: Audit & Warn Mode

```bash
# Tạo namespace với audit và warn (không enforce)
kubectl create namespace pss-audit-ns
kubectl label namespace pss-audit-ns \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/audit-version=latest \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/warn-version=latest

# Deploy pod vi phạm — sẽ được cho qua nhưng có warning
kubectl apply -f manifests/pod-violation-test.yaml -n pss-audit-ns
# Warning: would violate PodSecurity "restricted:latest": ...
# pod/violation-pod created (vẫn được tạo)
```

### Step 9: fsGroup — Volume Permission

```bash
# fsGroup đặt GID cho tất cả files trong mounted volumes
# Hữu ích khi container cần write vào volumes được mount

# Kiểm tra volume ownership
kubectl exec -n security-lab secure-pod -- ls -la /data/
# drwxrwsr-x ... 2000 2000 ... /data/
# GID 2000 = fsGroup được set
```

### Step 10: Xem tất cả Pod Security violations trong audit logs

```bash
# Nếu audit logging được enabled (thường trong production clusters)
# Tìm PSS violations:
kubectl get events -n restricted-ns | grep -i "forbidden\|violat"

# Kiểm tra namespace labels
kubectl get namespaces --show-labels | grep pod-security
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
echo "=== Kiểm tra các Pods đang chạy ==="
kubectl get pods -n security-lab

echo "=== Kiểm tra Security Context của secure-pod ==="
kubectl get pod secure-pod -n security-lab -o jsonpath='{.spec.securityContext}' | python3 -m json.tool

echo "=== Kiểm tra Container Security Context ==="
kubectl get pod secure-pod -n security-lab \
  -o jsonpath='{.spec.containers[0].securityContext}' | python3 -m json.tool

echo "=== Kiểm tra Namespace PSS Labels ==="
kubectl get namespace restricted-ns -o jsonpath='{.metadata.labels}' | python3 -m json.tool

echo "=== Test: Pod có đang chạy với non-root? ==="
kubectl exec -n security-lab secure-pod -- id 2>/dev/null | grep -v "uid=0"
echo "✅ Running as non-root"

echo "=== Test: Root filesystem có read-only không? ==="
kubectl exec -n security-lab secure-pod -- touch /blocked 2>&1 | grep -i "read-only" && echo "✅ Root FS is read-only"
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xóa tất cả resources
kubectl delete -f manifests/ --ignore-not-found=true

# Xóa namespaces
kubectl delete namespace security-lab restricted-ns pss-audit-ns --ignore-not-found=true

# Verify cleanup
kubectl get pods -n security-lab 2>/dev/null || echo "Namespace đã được xóa"
```

---

## 💡 Tips & Gotchas

### ⚠️ `runAsNonRoot: true` không tự đổi UID
`runAsNonRoot: true` CHỈ kiểm tra rằng UID != 0. Nếu image mặc định chạy với root (UID 0), pod sẽ **fail**. Bạn phải set `runAsUser` hoặc build image với USER khác:
```dockerfile
# Trong Dockerfile
RUN adduser -D -u 1000 appuser
USER appuser
```

### ⚠️ `readOnlyRootFilesystem` cần emptyDir cho tmp
Khi bật `readOnlyRootFilesystem`, nhiều apps cần ghi vào `/tmp`. Giải pháp: mount `emptyDir` vào `/tmp`:
```yaml
volumeMounts:
- name: tmp-dir
  mountPath: /tmp
volumes:
- name: tmp-dir
  emptyDir: {}
```

### ⚠️ PSS Restricted yêu cầu seccompProfile
Từ Kubernetes 1.25+, PSS Restricted yêu cầu seccompProfile phải được set:
```yaml
securityContext:
  seccompProfile:
    type: RuntimeDefault  # Hoặc Localhost với custom profile
```

### ⚠️ `allowPrivilegeEscalation: false` và setuid binaries
Một số tools như `sudo`, `su` cần setuid bits (CAP_SETUID). Khi set `allowPrivilegeEscalation: false`, các tools này sẽ không hoạt động — đây là điều mong muốn!

### 💡 Check Pod Security violation trước khi enforce
Luôn bắt đầu với `audit` + `warn` mode để hiểu tác động, sau đó mới chuyển sang `enforce`:
```bash
kubectl label namespace production \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted
# Chờ và xem warnings, sau đó:
kubectl label namespace production \
  pod-security.kubernetes.io/enforce=restricted
```

### 💡 Dùng `kubectl auth can-i` với SecurityContext
```bash
# Kiểm tra xem pod có thể chạy với UID cụ thể không
kubectl auth can-i use podsecuritypolicy/privileged \
  --as=system:serviceaccount:default:default
```

---

## 📚 Tham khảo (References)

- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)
- [Configure a Security Context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [Linux Capabilities](https://man7.org/linux/man-pages/man7/capabilities.7.html)
- [Seccomp Security Profiles](https://kubernetes.io/docs/tutorials/security/seccomp/)

## 🔗 Next Lab

➡️ **[Lab 27 — Zero-trust Networking](../lab-27-zero-trust-network/README.md)**
