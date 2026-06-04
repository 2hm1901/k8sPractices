# Lab 14 — Endpoints & External Services

## 🎯 Mục tiêu (Objectives)

Sau lab này bạn sẽ hiểu và thực hành được:
- Hiểu mối quan hệ giữa **Service → Endpoints → EndpointSlices**
- Tạo **Service without selector** để quản lý traffic thủ công
- Tạo **Manual Endpoints** trỏ tới external IP
- Dùng **ExternalName** service cho DNS aliasing
- Kết nối cluster tới **external database / API** (outside cluster)
- Hiểu **EndpointSlice** và tại sao nó thay thế Endpoints

---

## 📋 Prerequisites

- Cluster đang chạy
- `kubectl` configured
- Kiến thức về Services từ Lab 10

```bash
kubectl cluster-info
kubectl get nodes
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Service → Endpoints Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  Normal Service (with selector):                                │
│                                                                 │
│  Service {selector: app=backend}                                │
│      │                                                          │
│      │ kube-controller-manager tự động tạo/update              │
│      ▼                                                          │
│  Endpoints {                                                    │
│    subsets: [{                                                  │
│      addresses: [{ip: 10.244.0.5}, {ip: 10.244.0.6}],         │
│      ports: [{port: 8080}]                                      │
│    }]                                                           │
│  }                                                              │
│      │                                                          │
│      │ kube-proxy reads and creates iptables rules              │
│      ▼                                                          │
│  Traffic routed to Pod IPs                                      │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  Service without selector:                                      │
│                                                                 │
│  Service {NO selector}                                          │
│      │                                                          │
│      │ Bạn tự tạo Endpoints thủ công                           │
│      ▼                                                          │
│  Endpoints {                                                    │
│    subsets: [{                                                  │
│      addresses: [{ip: 203.0.113.50}],  ← External IP!          │
│      ports: [{port: 5432}]             ← External DB port      │
│    }]                                                           │
│  }                                                              │
└─────────────────────────────────────────────────────────────────┘
```

### EndpointSlice vs Endpoints

```
Endpoints (cũ):
  - 1 object chứa TẤT CẢ Pod IPs
  - Khi có 1 Pod thay đổi → phải update toàn bộ object
  - Vấn đề với clusters lớn (1000+ pods per service)

EndpointSlice (mới, K8s 1.17+):
  - Mỗi slice chứa tối đa 100 endpoints
  - Chỉ update slice bị ảnh hưởng → hiệu quả hơn
  - Tự động managed bởi K8s khi service có selector
  - Hỗ trợ dual-stack (IPv4 + IPv6)
  - Topology information (node, zone)
```

### ExternalName vs Manual Endpoints

```
ExternalName:
  DNS alias, trả về CNAME
  Không có ClusterIP
  Không có iptables rules
  
  Khi pod query "my-svc.ns.svc.cluster.local":
  → CoreDNS trả về CNAME: "external-api.example.com"
  → Pod resolve "external-api.example.com" ra IP

Manual Endpoints:
  Có ClusterIP
  Có iptables rules
  Transparent đến pod (pod không biết đây là external)
  
  Khi pod query "my-svc.ns.svc.cluster.local":
  → CoreDNS trả về ClusterIP
  → iptables forward đến external IP
```

### Khi nào dùng cái nào?

| Scenario | Solution |
|----------|----------|
| External service có hostname (DNS) | ExternalName |
| External service có static IP | Service + manual Endpoints |
| Migrate từ external vào cluster | Service + manual Endpoints (dễ chuyển sang selector sau) |
| External HTTPS API | ExternalName (preserve TLS SNI) |
| External DB với IP cố định | Service + manual Endpoints |

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Chuẩn bị Namespace

```bash
kubectl create namespace lab14
```

---

### Step 2: Khám phá Endpoints của Service thông thường

```bash
# Tạo một deployment và service bình thường
kubectl create deployment normal-app --image=nginx:1.25 --replicas=3 -n lab14
kubectl expose deployment normal-app --port=80 --target-port=80 -n lab14

# Xem Service
kubectl get svc normal-app -n lab14

# Xem Endpoints được tự động tạo
kubectl get endpoints normal-app -n lab14
# NAME         ENDPOINTS                                            AGE
# normal-app   10.244.0.10:80,10.244.0.11:80,10.244.0.12:80       30s

# Xem chi tiết
kubectl describe endpoints normal-app -n lab14
# Name:         normal-app
# Namespace:    lab14
# Labels:       app=normal-app
# Annotations:  endpoints.kubernetes.io/last-change-trigger-time: ...
# Subsets:
#   Addresses:  10.244.0.10,10.244.0.11,10.244.0.12
#   NotReadyAddresses: <none>
#   Ports:
#     Name     Port  Protocol
#     ----     ----  --------
#     <unset>  80    TCP

# Xem EndpointSlices (mới hơn)
kubectl get endpointslices -n lab14
# NAME               ADDRESSTYPE   PORTS   ENDPOINTS                                AGE
# normal-app-xxxxx   IPv4          80      10.244.0.10,10.244.0.11,10.244.0.12      30s

kubectl describe endpointslice -n lab14
# Name:         normal-app-xxxxx
# Namespace:    lab14
# Labels:       endpointslice.kubernetes.io/managed-by=endpointslice-controller.k8s.io
#               kubernetes.io/service-name=normal-app
# Endpoints:
#   - Addresses:  10.244.0.10
#     Conditions:
#       Ready:    true
#     TargetRef:  pod/normal-app-xxx-yyy
#     NodeName:   minikube
#     Zone:       <unset>
```

Scale và xem Endpoints tự động update:
```bash
kubectl scale deployment normal-app --replicas=5 -n lab14

# Watch Endpoints update
kubectl get endpoints normal-app -n lab14 -w
# normal-app   10.244.0.10:80,10.244.0.11:80,10.244.0.12:80  → sau scale:
# normal-app   10.244.0.10:80,10.244.0.11:80,...10.244.0.14:80
```

---

### Step 3: Service for External Database (No Selector)

Scenario: Cluster cần kết nối đến PostgreSQL chạy ở IP `203.0.113.50` (external server).

```bash
kubectl apply -f manifests/service-external-db.yaml -n lab14
```

```bash
kubectl get svc external-postgres -n lab14
# NAME               TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
# external-postgres  ClusterIP   10.96.XXX.XXX   <none>        5432/TCP   10s

# Chú ý: Không có Endpoints tự động!
kubectl get endpoints external-postgres -n lab14
# NAME               ENDPOINTS   AGE
# external-postgres  <none>      10s   ← Trống!
```

---

### Step 4: Tạo Manual Endpoints

```bash
kubectl apply -f manifests/endpoints-external-db.yaml -n lab14
```

```bash
kubectl get endpoints external-postgres -n lab14
# NAME               ENDPOINTS            AGE
# external-postgres  203.0.113.50:5432    10s  ← External IP!

kubectl describe endpoints external-postgres -n lab14
# Subsets:
#   Addresses:  203.0.113.50
#   Ports:
#     Name     Port  Protocol
#     ----     ----  --------
#     postgres 5432  TCP
```

Test kết nối (sẽ fail vì IP giả, nhưng thấy traffic đi đúng hướng):
```bash
kubectl run pg-client --image=postgres:15-alpine -n lab14 \
  --env="PGPASSWORD=secret" --rm -it --restart=Never \
  -- psql -h external-postgres -U app_user -d myapp -c "SELECT version();"
# Nếu external IP là thật, sẽ kết nối được!
# psql: error: connection to server at "external-postgres" ...: Connection refused
# → Traffic đã đến đúng host (203.0.113.50) nhưng service không chạy
```

Kiểm tra DNS resolution:
```bash
kubectl run dns-check --image=busybox:1.36 -n lab14 --rm -it --restart=Never \
  -- nslookup external-postgres
# Server:    10.96.0.10
# Address 1: 10.96.0.10
# Name:      external-postgres
# Address 1: 10.96.XXX.XXX  ← ClusterIP của service
```

---

### Step 5: ExternalName Service

```bash
kubectl apply -f manifests/service-externalname-api.yaml -n lab14
```

```bash
kubectl get svc external-api -n lab14
# NAME           TYPE           CLUSTER-IP   EXTERNAL-IP              PORT(S)   AGE
# external-api   ExternalName   <none>       httpbin.org              <none>    10s
```

Test ExternalName:
```bash
# Kết nối qua ExternalName service
kubectl run curl-test --image=curlimages/curl -n lab14 --rm -it --restart=Never \
  -- curl -s https://external-api/get 2>/dev/null | head -20

# Xem DNS response (CNAME)
kubectl run dns-check --image=busybox:1.36 -n lab14 --rm -it --restart=Never \
  -- nslookup external-api.lab14.svc.cluster.local
# Server:    10.96.0.10
# Address 1: 10.96.0.10
# 
# Name:      external-api.lab14.svc.cluster.local
# Address 1: 3.218.X.X   ← Actual IP của httpbin.org (sau CNAME resolution)
```

---

### Step 6: Migration Pattern (External → Internal)

Đây là pattern phổ biến khi migrate legacy services vào Kubernetes:

```bash
# Phase 1: Trỏ service vào external server
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: legacy-db
  namespace: lab14
spec:
  ports:
    - port: 5432
      targetPort: 5432
---
apiVersion: v1
kind: Endpoints
metadata:
  name: legacy-db
  namespace: lab14
subsets:
  - addresses:
      - ip: 203.0.113.100  # Legacy external server
    ports:
      - port: 5432
EOF

# Ứng dụng kết nối qua: legacy-db.lab14.svc.cluster.local:5432

# Phase 2: Khi đã migrate DB vào cluster, chỉ cần thêm selector
# Xóa manual Endpoints và thêm selector vào Service
kubectl patch svc legacy-db -n lab14 -p '{"spec":{"selector":{"app":"postgres"}}}'
# kubectl delete endpoints legacy-db -n lab14  # (auto-managed endpoints sẽ thay thế)

# Ứng dụng KHÔNG CẦN thay đổi config - vẫn dùng cùng Service name!
```

---

### Step 7: Multiple External IPs với Load Balancing

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: multi-external
  namespace: lab14
spec:
  ports:
    - port: 80
      targetPort: 80
---
apiVersion: v1
kind: Endpoints
metadata:
  name: multi-external
  namespace: lab14
subsets:
  - addresses:
      - ip: 1.2.3.4    # Server 1
      - ip: 1.2.3.5    # Server 2
      - ip: 1.2.3.6    # Server 3
    ports:
      - port: 80
EOF
```

```bash
kubectl get endpoints multi-external -n lab14
# NAME             ENDPOINTS                        AGE
# multi-external   1.2.3.4:80,1.2.3.5:80,1.2.3.6:80   10s
# → kube-proxy sẽ load balance giữa 3 IPs!
```

---

### Step 8: Xem EndpointSlices Chi Tiết

```bash
# EndpointSlices có thêm metadata hữu ích
kubectl get endpointslices -n lab14 -o wide

# Topology info (nếu có)
kubectl get endpointslice -n lab14 normal-app-xxxxx -o yaml
# ...
# endpoints:
# - addresses:
#   - 10.244.0.10
#   conditions:
#     ready: true
#     serving: true
#     terminating: false
#   nodeName: minikube
#   targetRef:
#     kind: Pod
#     name: normal-app-xxx-yyy
#     namespace: lab14
```

Điểm khác biệt với Endpoints thông thường:
- `serving`: Pod đang serve traffic (khác `ready` trong shutdown grace period)
- `terminating`: Pod đang trong shutdown, nhưng vẫn serve
- `nodeName`: Biết pod ở node nào → topology-aware routing

---

## ✅ Kiểm tra kết quả (Verification)

```bash
echo "=== All Services in lab14 ==="
kubectl get svc -n lab14

echo ""
echo "=== All Endpoints in lab14 ==="
kubectl get endpoints -n lab14

echo ""
echo "=== All EndpointSlices in lab14 ==="
kubectl get endpointslices -n lab14

echo ""
echo "=== Service Details ==="
kubectl describe svc external-postgres -n lab14
kubectl describe svc external-api -n lab14

echo ""
echo "=== Endpoint Details ==="
kubectl describe endpoints external-postgres -n lab14

echo ""
echo "=== DNS Test for ExternalName ==="
kubectl run dns-verify --image=busybox:1.36 -n lab14 --rm -it --restart=Never \
  -- sh -c "nslookup external-postgres && nslookup external-api.lab14.svc.cluster.local"
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
kubectl delete namespace lab14
# namespace "lab14" deleted

# Kiểm tra đã sạch
kubectl get all -n lab14
# Error from server (NotFound): namespaces "lab14" not found
```

---

## 💡 Tips & Gotchas

1. **Endpoint và Service phải cùng tên**: Manual Endpoints phải có metadata.name trùng với Service. Nếu sai tên, Service sẽ không tìm thấy Endpoints.

2. **ExternalName không có ClusterIP**: `kubectl get svc` sẽ hiển thị `CLUSTER-IP: <none>` cho ExternalName. Không thể dùng ClusterIP approach với ExternalName.

3. **External IPs trong Endpoints không cần là public IP**: Có thể là private IP của external server (ví dụ: 192.168.1.100), miễn là nodes trong cluster có thể route đến đó.

4. **EndpointSlice limit**: Mỗi EndpointSlice chứa tối đa 100 endpoints. Service có 500 pods → 5 EndpointSlices.

5. **Readiness của manual Endpoints**: Manual Endpoints không có readiness check. Tất cả IPs trong `addresses` đều được coi là ready. Dùng `notReadyAddresses` để mark là not ready.

6. **ExternalName và TLS**: ExternalName forward DNS, không forward TCP. Nếu external service dùng HTTPS với strict SNI, pod phải dùng đúng hostname trong TLS ClientHello.

7. **Loopback không được phép**: Không thể dùng `127.0.0.1` trong Endpoints. Nếu cần localhost của Node, dùng IP của Node thay thế.

8. **Kube-proxy reload**: Khi Endpoints thay đổi, kube-proxy cần một chút thời gian (~1-2s) để update iptables rules. Có thể có brief downtime.

---

## 📚 Tham khảo (References)

- [Service without selector](https://kubernetes.io/docs/concepts/services-networking/service/#services-without-selectors)
- [EndpointSlices](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/)
- [ExternalName Services](https://kubernetes.io/docs/concepts/services-networking/service/#externalname)
- [Headless Services](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services)

---

## 🔗 Next Lab

👉 [Lab 15 — Persistent Volumes](../lab-15-persistent-volumes/README.md)
