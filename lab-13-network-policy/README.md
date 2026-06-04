# Lab 13 — NetworkPolicy

## 🎯 Mục tiêu (Objectives)

Sau lab này bạn sẽ hiểu và thực hành được:
- Tại sao K8s mặc định **allow-all** traffic giữa Pods
- **CNI prerequisites** cho NetworkPolicy (không phải CNI nào cũng support)
- Phân biệt **Ingress** và **Egress** policy (theo góc nhìn của Pod)
- **Label-based** peer selection và **namespace selector**
- Giới hạn **port/protocol** specific
- Pattern **Default Deny All** → mở dần từng kết nối
- Xây dựng mô hình bảo mật **Zero-Trust** cho microservices

---

## 📋 Prerequisites

- CNI hỗ trợ NetworkPolicy: **Calico**, **Cilium**, **Weave**, **Canal**
  - ⚠️ **Flannel** KHÔNG support NetworkPolicy!
  - Minikube: `minikube start --cni=calico` hoặc `--cni=cilium`
- `kubectl` configured

```bash
# Kiểm tra CNI đang dùng
kubectl get pods -n kube-system | grep -E "calico|cilium|weave|flannel"
# calico-node-xxxxx   1/1   Running   0   2d  ← OK
# cilium-xxxxx        1/1   Running   0   2d  ← OK
# flannel-xxxxx       ...                     ← NetworkPolicy sẽ bị IGNORE!
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Default Behavior (Không có NetworkPolicy)

```
┌─────────────────────────────────────────────────────────┐
│  Kubernetes Cluster (No NetworkPolicy)                  │
│                                                         │
│  frontend ──────────────────────────────▶ backend      │
│  frontend ──────────────────────────────▶ database     │  ← Nguy hiểm!
│  backend  ──────────────────────────────▶ database     │
│  any-pod  ──────────────────────────────▶ any-pod      │  ← Flat network
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Với NetworkPolicy (Zero-Trust)

```
┌─────────────────────────────────────────────────────────┐
│  Kubernetes Cluster (NetworkPolicy Applied)             │
│                                                         │
│  frontend ──────────▶ backend   (ALLOWED)               │
│  frontend ─────────✗─ database  (DENIED!)               │
│  backend  ──────────▶ database  (ALLOWED)               │
│  any-pod  ─────────✗─ database  (DENIED by default)     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### NetworkPolicy Selectors

```yaml
# Pod selector (trong cùng namespace)
podSelector:
  matchLabels:
    app: frontend

# Namespace selector
namespaceSelector:
  matchLabels:
    kubernetes.io/metadata.name: monitoring

# Combined (Pod TRONG namespace cụ thể)
namespaceSelector:
  matchLabels:
    name: monitoring
podSelector:
  matchLabels:
    app: prometheus

# IP block (CIDR)
ipBlock:
  cidr: 10.0.0.0/8
  except:
    - 10.96.0.0/12  # Exclude service CIDR
```

### Ingress vs Egress (từ góc nhìn của Pod bị apply policy)

```
                    [Ingress Policy]          [Egress Policy]
                         │                         │
  Other Pod ────────────▶│──────▶ THIS POD ──────▶│──────▶ Other Pod
                         │    (policy applied)     │
                    "Traffic vào"             "Traffic ra"
```

### Quan trọng: NetworkPolicy là ADDITIVE (OR logic)

```
Policy A: Allow frontend → backend on port 80
Policy B: Allow monitoring → backend on port 9090

Result: Backend nhận từ frontend:80 OR monitoring:9090
        (các policies được OR với nhau)
```

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Setup môi trường với Calico

```bash
# Khởi động Minikube với Calico CNI
minikube start --cni=calico

# Hoặc nếu đã có cluster
kubectl get nodes  # Kiểm tra cluster OK
```

Tạo namespaces và labels:
```bash
kubectl create namespace lab13
kubectl label namespace lab13 name=lab13

kubectl create namespace monitoring
kubectl label namespace monitoring name=monitoring kubernetes.io/metadata.name=monitoring
```

---

### Step 2: Deploy Frontend và Backend (Không có NetworkPolicy)

```bash
kubectl apply -f manifests/deployment-frontend.yaml -n lab13
kubectl apply -f manifests/deployment-backend.yaml -n lab13
```

```bash
kubectl get pods -n lab13 -o wide
# NAME                        READY   STATUS    IP
# backend-xxx-yyy             1/1     Running   10.244.0.20
# frontend-xxx-yyy            1/1     Running   10.244.0.21
```

Test kết nối mặc định (tất cả đều reach nhau):
```bash
# Lấy IPs
BACKEND_IP=$(kubectl get pod -n lab13 -l app=backend -o jsonpath='{.items[0].status.podIP}')
FRONTEND_POD=$(kubectl get pod -n lab13 -l app=frontend -o jsonpath='{.items[0].metadata.name}')

# Test: frontend → backend (sẽ SUCCESS trước khi có policy)
kubectl exec -it $FRONTEND_POD -n lab13 -- curl -s --connect-timeout 3 http://$BACKEND_IP:8080/
# {"message": "Backend API"}  ← Kết nối OK!

# Test: bất kỳ pod nào cũng access được backend
kubectl run test-pod --image=curlimages/curl -n lab13 --rm -it --restart=Never \
  -- curl -s --connect-timeout 3 http://$BACKEND_IP:8080/
# {"message": "Backend API"}  ← Cũng OK! Đây là vấn đề bảo mật!
```

---

### Step 3: Áp dụng Default Deny-All Policy

**Đây là bước đầu tiên của Zero-Trust - deny tất cả, rồi mở dần.**

```bash
kubectl apply -f manifests/netpol-deny-all.yaml -n lab13
```

Ngay lập tức test lại:
```bash
# frontend → backend bây giờ bị BLOCK
kubectl exec -it $FRONTEND_POD -n lab13 -- curl -s --connect-timeout 3 http://$BACKEND_IP:8080/
# curl: (28) Connection timed out  ← Bị chặn!

# Kết nối cũng bị block
kubectl run test-pod --image=curlimages/curl -n lab13 --rm -it --restart=Never \
  -- curl -s --connect-timeout 3 http://$BACKEND_IP:8080/
# curl: (28) Connection timed out  ← Bị chặn!
```

> ⚠️ **Lưu ý quan trọng**: Deny-all policy sẽ block **cả DNS** (port 53)! Các pods sẽ không resolve được tên. Ta cần allow DNS egress riêng.

---

### Step 4: Allow DNS Egress

```bash
kubectl apply -f manifests/netpol-allow-dns-egress.yaml -n lab13
```

Test DNS hoạt động lại:
```bash
kubectl exec -it $FRONTEND_POD -n lab13 -- nslookup kubernetes.default.svc.cluster.local
# Server:    10.96.0.10
# Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local
# Name:      kubernetes.default.svc.cluster.local
# ← DNS hoạt động, nhưng HTTP vẫn bị block
```

---

### Step 5: Allow Frontend → Backend

```bash
kubectl apply -f manifests/netpol-allow-frontend-to-backend.yaml -n lab13
```

Test:
```bash
# frontend → backend: ALLOWED
kubectl exec -it $FRONTEND_POD -n lab13 -- curl -s --connect-timeout 3 http://backend.lab13.svc.cluster.local:8080/
# {"message": "Backend API"}  ← Thành công!

# test-pod → backend: vẫn BLOCKED
kubectl run test-pod --image=curlimages/curl -n lab13 --rm -it --restart=Never \
  -- curl -s --connect-timeout 3 http://backend.lab13.svc.cluster.local:8080/
# curl: (28) Connection timed out  ← Vẫn bị chặn!
```

---

### Step 6: Allow Monitoring Namespace

```bash
kubectl apply -f manifests/netpol-allow-monitoring.yaml -n lab13

# Tạo test pod trong monitoring namespace
kubectl run prometheus --image=curlimages/curl -n monitoring --restart=Never \
  -- sleep 3600
```

Test:
```bash
# monitoring/prometheus → backend:9090: ALLOWED
kubectl exec -it prometheus -n monitoring \
  -- curl -s --connect-timeout 3 http://backend.lab13.svc.cluster.local:9090/metrics
# # HELP go_gc_duration_seconds ...  ← Metrics accessible!

# monitoring/prometheus → backend:8080: BLOCKED (chỉ allow port 9090)
kubectl exec -it prometheus -n monitoring \
  -- curl -s --connect-timeout 3 http://backend.lab13.svc.cluster.local:8080/
# curl: (28) Connection timed out  ← Port 8080 bị chặn!
```

---

### Step 7: Xem và Debug NetworkPolicies

```bash
# Xem tất cả policies
kubectl get networkpolicy -n lab13
# NAME                          POD-SELECTOR   AGE
# deny-all                      <none>         5m
# allow-dns-egress              <none>         4m
# allow-frontend-to-backend     app=backend    3m
# allow-monitoring-to-backend   app=backend    2m

# Describe chi tiết một policy
kubectl describe networkpolicy allow-frontend-to-backend -n lab13
# Name:         allow-frontend-to-backend
# Namespace:    lab13
# Created on:   2026-06-04 ...
# Labels:       <none>
# Spec:
#   PodSelector: app=backend
#   Allowing ingress traffic:
#     From Source:
#       PodSelector: app=frontend
#     To Ports:
#       Port: 8080/TCP
#   Not affecting egress traffic
#   Policy Types: Ingress
```

Dùng Cilium CLI (nếu dùng Cilium CNI):
```bash
cilium network policy get -n lab13
cilium monitor --type=drop  # Watch các packets bị drop
```

---

### Step 8: Namespace Isolation Pattern

Cô lập hoàn toàn namespace từ namespaces khác:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: namespace-isolation
  namespace: lab13
spec:
  podSelector: {}  # Apply tất cả pods
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: lab13  # Chỉ allow traffic từ cùng namespace
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: lab13
    - ports:           # Vẫn allow DNS
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
EOF
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
echo "=== NetworkPolicies in lab13 ==="
kubectl get networkpolicy -n lab13

echo ""
echo "=== Test Matrix ==="
BACKEND_SVC="backend.lab13.svc.cluster.local:8080"
FRONTEND_POD=$(kubectl get pod -n lab13 -l app=frontend -o jsonpath='{.items[0].metadata.name}')

echo "Test 1: frontend → backend (should ALLOW)"
kubectl exec -it $FRONTEND_POD -n lab13 -- \
  curl -s --connect-timeout 3 -o /dev/null -w "HTTP: %{http_code}\n" http://$BACKEND_SVC

echo ""
echo "Test 2: monitoring → backend metrics (should ALLOW port 9090)"
kubectl exec -it prometheus -n monitoring -- \
  curl -s --connect-timeout 3 -o /dev/null -w "HTTP: %{http_code}\n" \
  http://backend.lab13.svc.cluster.local:9090/metrics

echo ""
echo "Test 3: DNS resolution (should WORK)"
kubectl exec -it $FRONTEND_POD -n lab13 -- \
  nslookup backend.lab13.svc.cluster.local 2>&1 | grep -E "Address|Name"
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
kubectl delete namespace lab13
kubectl delete namespace monitoring
kubectl delete pod prometheus -n monitoring --force 2>/dev/null || true
```

---

## 💡 Tips & Gotchas

1. **Không có NetworkPolicy = Allow All**: K8s không có implicit deny. Phải tự tạo.

2. **CNI support**: Không phải mọi CNI đều implement NetworkPolicy. Nếu dùng Flannel, policies sẽ bị ignore hoàn toàn mà không có warning!

3. **Empty podSelector**: `podSelector: {}` chọn TẤT CẢ pods trong namespace.

4. **Policy OR not AND**: Nhiều policies trên cùng pod sẽ OR nhau. Không thể tạo AND logic bằng cách stack policies.

5. **Egress DNS**: Nếu apply deny-all egress, LUÔN phải allow DNS (port 53 UDP/TCP) riêng. Nếu không, tất cả service discovery sẽ fail.

6. **Không có REJECT, chỉ có DROP**: NetworkPolicy DROP packets (timeout), không REJECT. Client sẽ phải chờ timeout.

7. **Ingress Controller vẫn cần được allowed**: Nếu dùng Ingress, phải allow traffic từ namespace `ingress-nginx`:
   ```yaml
   - from:
     - namespaceSelector:
         matchLabels:
           kubernetes.io/metadata.name: ingress-nginx
   ```

8. **Monitoring/Logging**: Prometheus cần scrape pods → phải có Egress policy allow từ monitoring namespace.

---

## 📚 Tham khảo (References)

- [Network Policies - Official Docs](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [NetworkPolicy Editor (visual)](https://editor.networkpolicy.io/)
- [Calico NetworkPolicy](https://docs.tigera.io/calico/latest/network-policy/)
- [Kubernetes Network Policy Recipes](https://github.com/ahmetb/kubernetes-network-policy-recipes)

---

## 🔗 Next Lab

👉 [Lab 14 — Endpoints & External Services](../lab-14-endpoints/README.md)
