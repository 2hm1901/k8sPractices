# Lab 11 — DNS & Service Discovery

## 🎯 Mục tiêu (Objectives)

Sau lab này bạn sẽ hiểu và thực hành được:
- Kiến trúc **CoreDNS** trong Kubernetes cluster
- DNS resolution format: `service.namespace.svc.cluster.local`
- Pod DNS: `pod-ip.namespace.pod.cluster.local`
- Các **DNS policies**: `ClusterFirst`, `ClusterFirstWithHostNet`, `Default`, `None`
- Tuỳ chỉnh DNS config cho Pod với `dnsConfig`
- Debug DNS với `nslookup` và `dig` trong pod
- Hiểu và cấu hình **ndots** setting

---

## 📋 Prerequisites

- Cluster đang chạy với CoreDNS deployed
- `kubectl` configured

```bash
# Kiểm tra CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
# NAME                       READY   STATUS    RESTARTS   AGE
# coredns-5d78c9869d-abc12   1/1     Running   0          2d
# coredns-5d78c9869d-def34   1/1     Running   0          2d
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### CoreDNS Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                       │
│                                                             │
│  Pod                                                        │
│  ┌──────────────────┐                                       │
│  │  /etc/resolv.conf│                                       │
│  │  nameserver 10.96.0.10  ◄──── CoreDNS ClusterIP         │
│  │  search default.svc.cluster.local svc.cluster.local      │
│  │         cluster.local                                    │
│  │  options ndots:5                                         │
│  └──────────┬───────┘                                       │
│             │ DNS query                                     │
│             ▼                                               │
│  ┌──────────────────────────────────────────────┐           │
│  │  CoreDNS (kube-dns service: 10.96.0.10)      │           │
│  │                                              │           │
│  │  ┌─────────────┐  ┌────────────────────┐    │           │
│  │  │  kubernetes │  │  forward (to        │    │           │
│  │  │  plugin     │  │  upstream DNS)      │    │           │
│  │  │  (in-cluster│  │  8.8.8.8, 8.8.4.4  │    │           │
│  │  │  records)   │  └────────────────────┘    │           │
│  │  └─────────────┘                            │           │
│  └──────────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────────┘
```

### DNS Name Format

```
Service DNS:
  <service-name>.<namespace>.svc.<cluster-domain>
  my-svc.my-ns.svc.cluster.local

Pod DNS (nếu hostname được đặt):
  <pod-ip-dashes>.<namespace>.pod.<cluster-domain>
  10-244-0-5.my-ns.pod.cluster.local

Headless Service Pod:
  <pod-hostname>.<svc-name>.<namespace>.svc.<cluster-domain>
  web-0.my-headless.my-ns.svc.cluster.local
```

### DNS Resolution Flow với ndots:5

```
Query: "my-svc" từ namespace "default"

1. my-svc.default.svc.cluster.local  ← thử trước (search domain 1)
2. my-svc.svc.cluster.local          ← search domain 2
3. my-svc.cluster.local              ← search domain 3
4. my-svc.                           ← absolute lookup (fallback)

Query: "my-svc.other-ns" (có 1 dot < ndots:5)
→ Cũng thử các search domains trước, rồi fallback ra internet
```

### DNS Policies

| Policy | Description |
|--------|-------------|
| `ClusterFirst` | Mặc định: query CoreDNS trước, non-cluster queries forward ra ngoài |
| `ClusterFirstWithHostNet` | Dùng với `hostNetwork: true` |
| `Default` | Dùng DNS của Node (không dùng CoreDNS) |
| `None` | Tắt hoàn toàn, phải tự set `dnsConfig` |

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Chuẩn bị Namespace và Services

```bash
kubectl create namespace lab11
```

Tạo một số services để test:
```bash
# Service trong namespace lab11
kubectl create deployment web-app --image=nginx:1.25 -n lab11
kubectl expose deployment web-app --port=80 -n lab11

# Service trong namespace default (để test cross-namespace)
kubectl create deployment other-app --image=nginx:1.25
kubectl expose deployment other-app --port=80
```

---

### Step 2: Deploy DNS Debug Pod (dnsutils)

```bash
kubectl apply -f manifests/pod-dnsutils.yaml -n lab11
```

Đợi pod ready:
```bash
kubectl wait --for=condition=Ready pod/dnsutils -n lab11 --timeout=60s
```

Vào pod để debug:
```bash
kubectl exec -it dnsutils -n lab11 -- /bin/bash
```

---

### Step 3: Kiểm tra /etc/resolv.conf

Bên trong pod dnsutils:
```bash
cat /etc/resolv.conf
# search lab11.svc.cluster.local svc.cluster.local cluster.local
# nameserver 10.96.0.10
# options ndots:5
```

> **Giải thích:**
> - `search`: danh sách domain được thêm vào khi query không đủ dots
> - `nameserver`: IP của CoreDNS service
> - `ndots:5`: nếu query có < 5 dots, thử search domains trước

---

### Step 4: Test DNS Resolution

Bên trong pod dnsutils:

```bash
# Test 1: Short name (cùng namespace)
nslookup web-app
# Server:    10.96.0.10
# Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local
# Name:      web-app
# Address 1: 10.96.XXX.XXX

# Test 2: FQDN trong cùng namespace
nslookup web-app.lab11.svc.cluster.local
# Same result

# Test 3: Cross-namespace (phải dùng namespace)
nslookup other-app.default.svc.cluster.local
# Hoạt động được!

# Test 4: Dùng 'dig' để xem chi tiết
dig web-app.lab11.svc.cluster.local
# ;; ANSWER SECTION:
# web-app.lab11.svc.cluster.local. 30 IN A 10.96.XXX.XXX

# Test 5: Xem SRV record (có port info)
dig SRV _http._tcp.web-app.lab11.svc.cluster.local
# ;; ANSWER SECTION:
# _http._tcp.web-app.lab11.svc.cluster.local. 30 IN SRV 0 100 80 web-app.lab11.svc.cluster.local.

# Test 6: DNS lookup external domain
nslookup google.com
# → Forwarded đến upstream DNS (8.8.8.8 hoặc node DNS)

# Thoát khỏi pod
exit
```

---

### Step 5: Pod DNS Records

```bash
# Xem IP của một pod
kubectl get pods -n lab11 -o wide
# NAME                       READY   STATUS    IP
# web-app-xxx-yyy            1/1     Running   10.244.0.15

# Format: IP-dashes.namespace.pod.cluster.local
# 10.244.0.15 → 10-244-0-15.lab11.pod.cluster.local

kubectl exec -it dnsutils -n lab11 -- nslookup 10-244-0-15.lab11.pod.cluster.local
```

---

### Step 6: Headless Service DNS

Headless service (clusterIP: None) trả về Pod IPs trực tiếp:

```bash
# Tạo headless service
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: web-headless
  namespace: lab11
spec:
  clusterIP: None  # Headless!
  selector:
    app: web-app
  ports:
    - port: 80
EOF
```

```bash
# Test: DNS trả về multiple A records (Pod IPs)
kubectl exec -it dnsutils -n lab11 -- nslookup web-headless.lab11.svc.cluster.local
# Name:      web-headless.lab11.svc.cluster.local
# Address 1: 10.244.0.15 10-244-0-15.lab11.pod.cluster.local
# Address 2: 10.244.0.16 10-244-0-16.lab11.pod.cluster.local
# (Trả về các Pod IPs, không phải ClusterIP!)
```

---

### Step 7: Custom DNS Policy

```bash
# Pod với DNS policy = None và custom config
kubectl apply -f manifests/pod-custom-dns.yaml -n lab11

kubectl exec -it pod-custom-dns -n lab11 -- cat /etc/resolv.conf
# nameserver 8.8.8.8
# nameserver 8.8.4.4
# search custom.search.example.com
# options ndots:2
```

---

### Step 8: CoreDNS ConfigMap

Xem cấu hình CoreDNS hiện tại:
```bash
kubectl get configmap coredns -n kube-system -o yaml
```

Output sẽ hiển thị `Corefile`:
```
Corefile: |
  .:53 {
      errors
      health {
         lameduck 5s
      }
      ready
      kubernetes cluster.local in-addr.arpa ip6.arpa {
         pods insecure
         fallthrough in-addr.arpa ip6.arpa
         ttl 30
      }
      prometheus :9153
      forward . /etc/resolv.conf {
         max_concurrent 1000
      }
      cache 30
      loop
      reload
      loadbalance
  }
```

Apply custom CoreDNS config (thêm stub zone):
```bash
kubectl apply -f manifests/configmap-coredns-custom.yaml

# Kiểm tra CoreDNS đã reload
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system
```

---

### Step 9: Debug DNS Issues

Kỹ thuật debug khi DNS không hoạt động:

```bash
# 1. Kiểm tra CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# 2. Xem logs CoreDNS
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# 3. Test từ pod
kubectl exec -it dnsutils -n lab11 -- nslookup kubernetes.default

# 4. Kiểm tra kube-dns service
kubectl get svc kube-dns -n kube-system
# NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
# kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   2d

# 5. Test connectivity đến CoreDNS
kubectl exec -it dnsutils -n lab11 -- nc -zv 10.96.0.10 53

# 6. Kiểm tra NetworkPolicy có block DNS không
kubectl get networkpolicy -A

# 7. Enable CoreDNS logging (tạm thời)
kubectl edit configmap coredns -n kube-system
# Thêm 'log' plugin vào Corefile
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# Summary check
echo "=== CoreDNS Status ==="
kubectl get pods -n kube-system -l k8s-app=kube-dns

echo ""
echo "=== CoreDNS Service ==="
kubectl get svc kube-dns -n kube-system

echo ""
echo "=== DNS Tests ==="
kubectl exec -it dnsutils -n lab11 -- sh -c "
  echo '--- Same namespace ---'
  nslookup web-app 2>&1 | grep -E 'Name|Address'
  echo '--- Cross namespace ---'
  nslookup other-app.default.svc.cluster.local 2>&1 | grep -E 'Name|Address'
  echo '--- External DNS ---'
  nslookup google.com 2>&1 | grep -E 'Name|Address' | head -3
"

echo ""
echo "=== Pod resolv.conf ==="
kubectl exec -it dnsutils -n lab11 -- cat /etc/resolv.conf
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
kubectl delete namespace lab11
kubectl delete deployment other-app
kubectl delete service other-app
```

---

## 💡 Tips & Gotchas

1. **ndots:5 gây latency**: Với ndots:5, mỗi short-name query sẽ thử 5+ DNS queries. Giải pháp: dùng FQDN (kết thúc bằng `.`), hoặc set `ndots:2` trong dnsConfig.

2. **DNS caching**: CoreDNS cache 30s theo mặc định. Nếu service thay đổi IP, có thể mất 30s để propagate.

3. **CoreDNS CPU spike**: Trong cluster lớn, CoreDNS có thể bị CPU spike. Giải pháp: NodeLocal DNSCache.

4. **DNS trong hostNetwork pod**: Pod với `hostNetwork: true` dùng DNS của host, không phải CoreDNS. Phải set `dnsPolicy: ClusterFirstWithHostNet`.

5. **Service trong namespace khác**: LUÔN dùng FQDN `svc.namespace.svc.cluster.local` khi cross-namespace để tránh ambiguity.

6. **PTR records**: CoreDNS tự động tạo reverse DNS (PTR) cho Pod IPs trong cluster CIDR.

---

## 📚 Tham khảo (References)

- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [CoreDNS in Kubernetes](https://kubernetes.io/docs/tasks/administer-cluster/coredns/)
- [Customizing DNS](https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/)
- [NodeLocal DNSCache](https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/)

---

## 🔗 Next Lab

👉 [Lab 12 — Ingress & Ingress Controller](../lab-12-ingress/README.md)
