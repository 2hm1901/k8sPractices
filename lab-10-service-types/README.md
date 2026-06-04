# Lab 10 — Service Types

## 🎯 Mục tiêu (Objectives)

Sau lab này bạn sẽ hiểu và thực hành được:
- Cách `kube-proxy` hoạt động với `iptables` / `ipvs` để forward traffic
- Tạo và kiểm tra **ClusterIP** service (internal-only)
- Expose ứng dụng ra ngoài cluster với **NodePort** (port range 30000–32767)
- Hiểu cơ chế **LoadBalancer** tích hợp với cloud provider
- Dùng **ExternalName** để map service tới external DNS
- Tạo **Service without selector** + manual Endpoints

---

## 📋 Prerequisites

- Lab 01–09 đã hoàn thành (có cluster đang chạy)
- `kubectl` configured và trỏ đúng context
- Minikube hoặc kind cluster

```bash
kubectl cluster-info
kubectl get nodes
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Kiến trúc Service trong Kubernetes

```
┌─────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                   │
│                                                         │
│  ┌─────────────┐     ┌─────────────────────────────┐   │
│  │  kube-proxy │────▶│  iptables / ipvs rules       │   │
│  │  (DaemonSet)│     │  (maintained on every node)  │   │
│  └─────────────┘     └─────────────────────────────┘   │
│         │                        │                      │
│         ▼                        ▼                      │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Service (Virtual IP - ClusterIP)                │   │
│  │  10.96.0.1  ──────────────────────────────────   │   │
│  └──────────────────────────────────────────────────┘   │
│         │                                               │
│    ┌────┴──────┐                                        │
│    ▼           ▼                                        │
│  Pod-1       Pod-2    (selected by label selector)      │
└─────────────────────────────────────────────────────────┘
```

### Bốn loại Service

| Type | Scope | Use Case |
|------|-------|----------|
| **ClusterIP** | Internal only | Microservice-to-microservice |
| **NodePort** | External via Node IP | Dev/testing, on-prem |
| **LoadBalancer** | External via LB | Production on cloud |
| **ExternalName** | DNS alias | Accessing external services |

### kube-proxy modes

```
iptables mode (default):
  - Rules được tạo trong iptables PREROUTING/OUTPUT chains
  - Random load balancing (stateless)
  - O(n) rule lookup

ipvs mode:
  - Dùng Linux IPVS (kernel-level load balancer)
  - Supports: rr, lc, dh, sh, sed, nq algorithms
  - O(1) lookup - tốt hơn với clusters lớn
```

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Tạo Namespace và Deploy Demo App

```bash
kubectl create namespace lab10
```

Apply deployment:
```bash
kubectl apply -f manifests/deployment-demo-app.yaml -n lab10
```

Kiểm tra pods:
```bash
kubectl get pods -n lab10 -o wide
# NAME                        READY   STATUS    RESTARTS   AGE   IP            NODE
# demo-app-7d9f4b8c6-abc12    1/1     Running   0          30s   10.244.0.5    minikube
# demo-app-7d9f4b8c6-def34    1/1     Running   0          30s   10.244.0.6    minikube
# demo-app-7d9f4b8c6-ghi56    1/1     Running   0          30s   10.244.0.7    minikube
```

---

### Step 2: ClusterIP Service

ClusterIP là loại mặc định - chỉ accessible trong cluster.

```bash
kubectl apply -f manifests/service-clusterip.yaml -n lab10
```

Kiểm tra service:
```bash
kubectl get svc -n lab10
# NAME             TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
# demo-clusterip   ClusterIP   10.96.142.200   <none>        80/TCP    10s

kubectl describe svc demo-clusterip -n lab10
# Name:              demo-clusterip
# Namespace:         lab10
# Selector:          app=demo-app
# Type:              ClusterIP
# IP:                10.96.142.200
# Port:              http  80/TCP
# TargetPort:        8080/TCP
# Endpoints:         10.244.0.5:8080,10.244.0.6:8080,10.244.0.7:8080
```

Test từ trong cluster:
```bash
# Tạo temporary pod để test
kubectl run test-pod --image=curlimages/curl:latest -n lab10 --rm -it --restart=Never \
  -- curl -s http://demo-clusterip.lab10.svc.cluster.local/

# Hoặc dùng ClusterIP trực tiếp
kubectl run test-pod --image=curlimages/curl:latest -n lab10 --rm -it --restart=Never \
  -- curl -s http://10.96.142.200/
```

Xem iptables rules (chạy trên node):
```bash
# Minikube: SSH vào node
minikube ssh

# Xem iptables rules cho service
sudo iptables -t nat -L KUBE-SERVICES | grep lab10
sudo iptables -t nat -L KUBE-SVC-XXXXXXXXXXXXXXXX  # chain của service

# Hoặc xem ipvs (nếu dùng ipvs mode)
sudo ipvsadm -Ln | grep 10.96.142.200
```

---

### Step 3: NodePort Service

NodePort mở một port (30000-32767) trên **tất cả** các nodes.

```bash
kubectl apply -f manifests/service-nodeport.yaml -n lab10
```

```bash
kubectl get svc demo-nodeport -n lab10
# NAME            TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
# demo-nodeport   NodePort   10.96.58.101    <none>        80:31234/TCP     10s
```

Lấy Node IP và test:
```bash
# Với Minikube
MINIKUBE_IP=$(minikube ip)
echo "Minikube IP: $MINIKUBE_IP"

# Test NodePort
curl http://$MINIKUBE_IP:31234/

# Với kind cluster
kubectl get nodes -o wide
# Dùng node internal IP + nodePort
```

Kiểm tra port range:
```bash
# Xem cấu hình API server
kubectl -n kube-system get pod kube-apiserver-minikube -o yaml | grep node-port-range
# --service-node-port-range=30000-32767  (default)
```

---

### Step 4: LoadBalancer Service

Trên Minikube cần chạy `minikube tunnel` để giả lập LoadBalancer:

```bash
# Terminal 1: chạy tunnel (cần sudo/admin)
minikube tunnel

# Terminal 2: apply và theo dõi
kubectl apply -f manifests/service-loadbalancer.yaml -n lab10

kubectl get svc demo-loadbalancer -n lab10 -w
# NAME                TYPE           CLUSTER-IP      EXTERNAL-IP    PORT(S)        AGE
# demo-loadbalancer   LoadBalancer   10.96.77.88     <pending>      80:31567/TCP   5s
# demo-loadbalancer   LoadBalancer   10.96.77.88     127.0.0.1      80:31567/TCP   30s
```

Test LoadBalancer:
```bash
EXTERNAL_IP=$(kubectl get svc demo-loadbalancer -n lab10 -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://$EXTERNAL_IP/
```

> **Note:** Trên production cloud (GKE, EKS, AKS), cloud provider sẽ tự động provision external load balancer và gán IP.

---

### Step 5: ExternalName Service

ExternalName không tạo ClusterIP mà trả về CNAME record.

```bash
kubectl apply -f manifests/service-externalname.yaml -n lab10
```

```bash
kubectl get svc demo-externalname -n lab10
# NAME                TYPE           CLUSTER-IP   EXTERNAL-IP                       PORT(S)   AGE
# demo-externalname   ExternalName   <none>       httpbin.org                       <none>    10s
```

Test DNS resolution:
```bash
kubectl run dns-test --image=busybox:1.36 -n lab10 --rm -it --restart=Never \
  -- nslookup demo-externalname.lab10.svc.cluster.local

# Kết quả:
# Server:    10.96.0.10
# Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local
#
# Name:      demo-externalname.lab10.svc.cluster.local
# Address 1: 54.208.X.X httpbin.org
```

---

### Step 6: Service Without Selector (Manual Endpoints)

Hữu ích khi kết nối đến external services với IP cố định.

```bash
# Tạo service không có selector
cat <<EOF | kubectl apply -f - -n lab10
apiVersion: v1
kind: Service
metadata:
  name: demo-manual-ep
spec:
  ports:
    - port: 80
      targetPort: 80
  # KHÔNG có selector
EOF

# Tạo Endpoints thủ công
cat <<EOF | kubectl apply -f - -n lab10
apiVersion: v1
kind: Endpoints
metadata:
  name: demo-manual-ep  # Phải trùng tên với Service
subsets:
  - addresses:
      - ip: 1.1.1.1       # Cloudflare DNS
      - ip: 8.8.8.8       # Google DNS
    ports:
      - port: 80
EOF
```

Kiểm tra:
```bash
kubectl get endpoints demo-manual-ep -n lab10
# NAME             ENDPOINTS                    AGE
# demo-manual-ep   1.1.1.1:80,8.8.8.8:80       10s
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# Xem tất cả services trong namespace
kubectl get svc -n lab10

# Expected output:
# NAME                TYPE           CLUSTER-IP      EXTERNAL-IP    PORT(S)          AGE
# demo-clusterip      ClusterIP      10.96.142.200   <none>         80/TCP           5m
# demo-nodeport       NodePort       10.96.58.101    <none>         80:31234/TCP     4m
# demo-loadbalancer   LoadBalancer   10.96.77.88     127.0.0.1      80:31567/TCP     3m
# demo-externalname   ExternalName   <none>          httpbin.org    <none>           2m

# Kiểm tra endpoints
kubectl get endpoints -n lab10

# Describe để xem chi tiết selector
kubectl describe svc -n lab10

# Xem labels của pods
kubectl get pods -n lab10 --show-labels
```

Port-forward để test ClusterIP từ local:
```bash
kubectl port-forward svc/demo-clusterip 8080:80 -n lab10 &
curl http://localhost:8080/
kill %1
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
kubectl delete namespace lab10
# namespace "lab10" deleted

# Nếu đang chạy minikube tunnel, Ctrl+C để dừng
```

---

## 💡 Tips & Gotchas

1. **ClusterIP "None" = Headless Service**: Dùng cho StatefulSets, trả về Pod IPs trực tiếp thay vì virtual IP.
   ```yaml
   spec:
     clusterIP: None  # Headless
   ```

2. **NodePort không chọn port**: Nếu không set `nodePort`, K8s sẽ auto-assign trong range 30000-32767.

3. **LoadBalancer vẫn có NodePort**: LoadBalancer thực ra là NodePort + external LB on top. Traffic flow: `LB → NodePort → ClusterIP → Pod`.

4. **ExternalName và TLS**: ExternalName chỉ làm DNS aliasing, không terminate TLS. Nếu external service dùng HTTPS, pod phải tự handle TLS.

5. **kube-proxy và iptables**: mỗi khi thêm/xóa service, kube-proxy phải re-write toàn bộ iptables chain. Với clusters lớn (>1000 services), hãy dùng `--proxy-mode=ipvs`.

6. **Service IP range**: Được set bởi `--service-cluster-ip-range` của API server (default: `10.96.0.0/12`).

---

## 📚 Tham khảo (References)

- [Service Types - Official Docs](https://kubernetes.io/docs/concepts/services-networking/service/)
- [kube-proxy modes](https://kubernetes.io/docs/reference/networking/virtual-ips/)
- [Topology Aware Routing](https://kubernetes.io/docs/concepts/services-networking/topology-aware-routing/)

---

## 🔗 Next Lab

👉 [Lab 11 — DNS & Service Discovery](../lab-11-dns-discovery/README.md)
