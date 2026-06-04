# Lab 27 — Zero-trust Networking

## 🎯 Mục tiêu (Objectives)

Sau khi hoàn thành lab này, bạn sẽ:
- Hiểu mô hình **Zero-trust networking** và nguyên tắc "never trust, always verify"
- Implement **Default Deny All** cho cả ingress lẫn egress
- Cho phép **DNS traffic** (port 53 UDP/TCP) — bước thiết yếu thường bị quên
- Cấu hình **service-to-service communication** có chọn lọc
- Cho phép **egress ra internet** với CIDR cụ thể
- Test NetworkPolicy với debug pod
- Hiểu tổng quan về **Service Mesh** (Istio/Linkerd) cho mTLS

---

## 📋 Prerequisites

- Lab 25–26 hoàn thành
- CNI plugin hỗ trợ NetworkPolicy (Calico, Cilium, Weave, hoặc Flannel+NetworkPolicy)
- `kubectl` với quyền admin

```bash
# Kiểm tra CNI có hỗ trợ NetworkPolicy không
kubectl get nodes -o wide
# Kiểm tra pods của CNI đang chạy
kubectl get pods -n kube-system | grep -E "calico|cilium|weave|flannel"
```

> ⚠️ **Lưu ý quan trọng**: NetworkPolicy CHỈ có tác dụng khi CNI plugin hỗ trợ.
> Nếu dùng `kind` với Flannel mặc định, policies sẽ không được enforce.
> Khuyến nghị: Cài Calico hoặc Cilium.

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Zero-Trust Model Principles

```
Traditional "Castle and Moat" Model (KHÔNG dùng):
┌─────────────────────────────────────────┐
│ Cluster (trusted zone)                  │
│  Pod A ←──────────────→ Pod B          │
│  ↑ Tất cả pods có thể talk với nhau ↑  │
└─────────────────────────────────────────┘
  Vấn đề: Nếu Pod A bị compromise, có thể
  tấn công tất cả pods khác!

Zero-Trust Model:
┌─────────────────────────────────────────┐
│ Cluster                                 │
│  [Frontend] ─(allowed)→ [Backend]       │
│  [Frontend] ─(BLOCKED)→ [Database]      │
│  [Backend]  ─(allowed)→ [Database]      │
│  [Monitoring] ─(scrape)→ [All pods]     │
│  [Unknown Pod] → BLOCKED everywhere     │
└─────────────────────────────────────────┘
  Nguyên tắc: Chỉ allow những gì cần thiết
```

### Three-Tier Application Architecture

```
Internet
    │
    ▼
[Ingress Controller]
    │  port 80/443
    ▼
[Frontend Pods] ──────── namespace: three-tier-app
    │  port 8080
    ▼
[Backend/API Pods]
    │  port 5432
    ▼
[Database Pods]

[Monitoring] ─(scrape 9090)→ [All Pods]
```

### NetworkPolicy Selectors

```
podSelector:       Chọn pods trong cùng namespace
namespaceSelector: Chọn tất cả pods trong namespace
ipBlock:           Chọn theo IP CIDR range
```

### DNS — Bước quan trọng nhất!

```
Khi Default Deny:
  Pod → DNS Query (port 53 UDP) → kube-dns → BLOCKED!
  Pod → curl backend-service → DNS resolution fails → App broken!

Giải pháp: Luôn allow DNS TRƯỚC KHI test các policies khác
```

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Tạo Namespace và Deploy Three-Tier App

```bash
# Tạo namespace
kubectl create namespace three-tier-app

# Deploy tất cả components
kubectl apply -f manifests/deployment-three-tier-app.yaml

# Kiểm tra tất cả pods đang chạy
kubectl get all -n three-tier-app
kubectl wait --for=condition=ready pod -l app=frontend -n three-tier-app --timeout=60s
kubectl wait --for=condition=ready pod -l app=backend -n three-tier-app --timeout=60s
```

### Step 2: Test Kết nối Trước Khi Apply Policies

```bash
# Lấy tên pods
FRONTEND=$(kubectl get pod -l app=frontend -n three-tier-app -o jsonpath='{.items[0].metadata.name}')
BACKEND=$(kubectl get pod -l app=backend -n three-tier-app -o jsonpath='{.items[0].metadata.name}')
DB=$(kubectl get pod -l app=database -n three-tier-app -o jsonpath='{.items[0].metadata.name}')

echo "Frontend: $FRONTEND"
echo "Backend: $BACKEND"
echo "Database: $DB"

# Test: Frontend có thể reach Backend không? (Trước khi có policy)
kubectl exec -n three-tier-app $FRONTEND -- \
  wget -qO- --timeout=3 http://backend-svc:8080/health 2>&1
# Expected: OK (chưa có NetworkPolicy)

# Test: Frontend có thể reach Database không? (Sẽ bị chặn sau khi apply policy)
kubectl exec -n three-tier-app $FRONTEND -- \
  nc -zv database-svc 5432 2>&1
# Expected hiện tại: Connection OK (chưa có policy)
```

### Step 3: Apply Default Deny All

```bash
# ⚠️ Sau bước này, TẤT CẢ traffic sẽ bị chặn!
kubectl apply -f manifests/netpol-default-deny-all.yaml

# Test ngay lập tức:
kubectl exec -n three-tier-app $FRONTEND -- \
  wget -qO- --timeout=3 http://backend-svc:8080/health 2>&1
# Expected: TIMEOUT hoặc connection refused ✅

# Kể cả DNS cũng bị chặn:
kubectl exec -n three-tier-app $FRONTEND -- \
  nslookup backend-svc 2>&1
# Expected: SERVFAIL hoặc timeout ✅
```

### Step 4: Allow DNS (THIẾT YẾU!)

```bash
kubectl apply -f manifests/netpol-allow-dns.yaml

# Test DNS đã hoạt động lại:
kubectl exec -n three-tier-app $FRONTEND -- \
  nslookup kubernetes.default 2>&1
# Expected: Server answer ✅

# Nhưng HTTP vẫn chưa hoạt động:
kubectl exec -n three-tier-app $FRONTEND -- \
  wget -qO- --timeout=3 http://backend-svc:8080/health 2>&1
# Expected: Connection refused (DNS OK, nhưng port 8080 chưa được allow) ✅
```

### Step 5: Allow Frontend → Backend

```bash
kubectl apply -f manifests/netpol-allow-frontend-backend.yaml

# Test Frontend → Backend (được phép):
kubectl exec -n three-tier-app $FRONTEND -- \
  wget -qO- --timeout=5 http://backend-svc:8080/health 2>&1
# Expected: {"status": "ok"} ✅

# Test Frontend → Database trực tiếp (vẫn bị chặn):
kubectl exec -n three-tier-app $FRONTEND -- \
  nc -zv database-svc 5432 2>&1
# Expected: TIMEOUT ✅ (không được phép kết nối trực tiếp DB)
```

### Step 6: Allow Backend → Database

```bash
kubectl apply -f manifests/netpol-allow-backend-db.yaml

# Test Backend → Database (được phép):
kubectl exec -n three-tier-app $BACKEND -- \
  nc -zv database-svc 5432 2>&1
# Expected: Connection succeeded ✅

# Confirm Frontend → Database vẫn bị chặn:
kubectl exec -n three-tier-app $FRONTEND -- \
  nc -zv database-svc 5432 2>&1
# Expected: TIMEOUT ✅
```

### Step 7: Allow Monitoring Scraping

```bash
# Tạo namespace monitoring (giả lập)
kubectl create namespace monitoring

# Deploy một pod giả lập Prometheus trong monitoring namespace
kubectl run prometheus --image=curlimages/curl:latest \
  --namespace=monitoring \
  --labels="app=prometheus" \
  --command -- sleep 3600

# Apply NetworkPolicy cho phép monitoring scrape
kubectl apply -f manifests/netpol-allow-monitoring-scrape.yaml

# Test Prometheus → Backend metrics (được phép):
PROM=$(kubectl get pod -l app=prometheus -n monitoring -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n monitoring $PROM -- \
  wget -qO- --timeout=5 http://backend-svc.three-tier-app.svc.cluster.local:9090/metrics 2>&1
```

### Step 8: Test Egress Internet Access

```bash
# Test: Backend pod có thể gọi internet không?
# (Sau Default Deny, egress cũng bị chặn)
kubectl exec -n three-tier-app $BACKEND -- \
  wget -qO- --timeout=5 https://api.example.com 2>&1
# Expected: TIMEOUT (egress bị chặn)

# Nếu cần allow specific egress, thêm ipBlock rule vào NetworkPolicy
# Xem chi tiết trong netpol-allow-frontend-backend.yaml
```

### Step 9: Debug NetworkPolicy Issues

```bash
# Deploy một debug pod không có labels (sẽ bị block tất cả)
kubectl run debug-pod --image=nicolaka/netshoot \
  --namespace=three-tier-app \
  --rm -it --restart=Never \
  -- bash

# Trong debug pod:
# nslookup backend-svc      # Test DNS
# curl -v backend-svc:8080  # Test HTTP
# nc -zv database-svc 5432  # Test TCP
# exit

# Xem NetworkPolicy đang áp dụng cho pod
kubectl describe networkpolicy -n three-tier-app

# Kiểm tra CNI logs (Calico):
kubectl logs -n kube-system -l app=calico-node --tail=20
```

### Step 10: Giới thiệu Service Mesh (mTLS với Istio)

```bash
# NetworkPolicy hoạt động ở Layer 3/4 (IP + Port)
# Service Mesh (Istio/Linkerd) hoạt động ở Layer 7 (HTTP/gRPC)
# + mTLS (Mutual TLS) → encrypt + authenticate traffic

# Kiểm tra Istio đã cài chưa (tùy cluster):
kubectl get pods -n istio-system 2>/dev/null || echo "Istio chưa cài"
kubectl get pods -n linkerd 2>/dev/null || echo "Linkerd chưa cài"

# Xem thêm: Lab chuyên sâu về Istio/Linkerd trong Phase 8
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
echo "=== Kiểm tra NetworkPolicies ==="
kubectl get networkpolicy -n three-tier-app

echo ""
echo "=== Chi tiết từng policy ==="
kubectl describe networkpolicy -n three-tier-app

echo ""
echo "=== Kiểm tra Pods ==="
kubectl get pods -n three-tier-app --show-labels

echo ""
echo "=== Test Matrix ==="
FRONTEND=$(kubectl get pod -l app=frontend -n three-tier-app -o jsonpath='{.items[0].metadata.name}')
BACKEND=$(kubectl get pod -l app=backend -n three-tier-app -o jsonpath='{.items[0].metadata.name}')

# Frontend → Backend (allowed)
result=$(kubectl exec -n three-tier-app $FRONTEND -- wget -qO- --timeout=3 http://backend-svc:8080/health 2>&1)
echo "Frontend → Backend: $result"

# Frontend → DB (blocked)
result=$(kubectl exec -n three-tier-app $FRONTEND -- nc -zv database-svc 5432 2>&1 || echo "BLOCKED")
echo "Frontend → Database: $result"

# Backend → DB (allowed)
result=$(kubectl exec -n three-tier-app $BACKEND -- nc -zv database-svc 5432 2>&1)
echo "Backend → Database: $result"
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xóa NetworkPolicies
kubectl delete -f manifests/ --ignore-not-found=true

# Xóa namespaces
kubectl delete namespace three-tier-app monitoring --ignore-not-found=true

# Verify
kubectl get all -n three-tier-app 2>/dev/null || echo "Cleaned up ✅"
```

---

## 💡 Tips & Gotchas

### ⚠️ DNS PHẢI được allow trước tiên
Đây là lỗi phổ biến nhất. Khi Default Deny, DNS (port 53 UDP/TCP) bị chặn. Apps sẽ không resolve service names:
```bash
# Dấu hiệu: "Could not resolve host: backend-svc"
# Giải pháp: Luôn apply DNS policy NGAY SAU Default Deny
```

### ⚠️ NetworkPolicy là additive (cộng dồn)
Nhiều NetworkPolicies áp dụng cho cùng một pod sẽ được **OR** lại với nhau:
- Policy 1: Allow từ frontend
- Policy 2: Allow từ monitoring
- Kết quả: Pod nhận traffic từ CŨNG frontend VÀ monitoring

### ⚠️ Empty podSelector = tất cả pods trong namespace
```yaml
# Chọn TẤT CẢ pods trong namespace:
podSelector: {}

# Chỉ chọn pods có label app=backend:
podSelector:
  matchLabels:
    app: backend
```

### ⚠️ Egress DNS cần cả UDP lẫn TCP
```yaml
# DNS dùng cả UDP (thông thường) và TCP (khi response > 512 bytes)
- port: 53
  protocol: UDP
- port: 53
  protocol: TCP
```

### 💡 Visualize NetworkPolicy
Dùng công cụ như `networkpolicy.io` để visualize:
```bash
# Export policy và paste vào https://editor.networkpolicy.io/
kubectl get networkpolicy -n three-tier-app -o yaml
```

### 💡 Cilium Network Policy Editor
Nếu dùng Cilium, có thể dùng CiliumNetworkPolicy (Layer 7 aware):
```bash
kubectl get ciliumnetworkpolicy -A 2>/dev/null
```

---

## 📚 Tham khảo (References)

- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [NetworkPolicy API Reference](https://kubernetes.io/docs/reference/kubernetes-api/policy-resources/network-policy-v1/)
- [NetworkPolicy Editor (Visual)](https://editor.networkpolicy.io/)
- [Calico Network Policy](https://docs.projectcalico.org/security/calico-network-policy)
- [Cilium Network Policy](https://docs.cilium.io/en/stable/network/kubernetes/policy/)
- [Istio Service Mesh](https://istio.io/latest/docs/)

## 🔗 Next Lab

➡️ **[Lab 28 — External Secret Management](../lab-28-external-secrets/README.md)**
