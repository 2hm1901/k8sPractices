# Lab 12 — Ingress & Ingress Controller

## 🎯 Mục tiêu (Objectives)

Sau lab này bạn sẽ hiểu và thực hành được:
- Tại sao cần Ingress (thay vì nhiều LoadBalancer)
- Cài đặt **NGINX Ingress Controller** trên Minikube
- Cấu hình **path-based routing** (`/api` vs `/`)
- Cấu hình **host-based routing** (`app1.local` vs `app2.local`)
- **TLS termination** với self-signed certificate
- Sử dụng **Ingress annotations** để control behavior
- **Rewrite rules** để transform request path

---

## 📋 Prerequisites

- Minikube hoặc cluster có hỗ trợ Ingress Controller
- `kubectl` configured
- `openssl` (để tạo self-signed cert)
- `helm` (tuỳ chọn)

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Vấn đề không có Ingress

```
Without Ingress (tốn kém):
  app1 → LoadBalancer (IP: 1.2.3.4:80)   ← mỗi LB tốn tiền trên cloud!
  app2 → LoadBalancer (IP: 1.2.3.5:80)
  app3 → LoadBalancer (IP: 1.2.3.6:80)

With Ingress (hiệu quả):
  app1.example.com  ─┐
  app2.example.com  ─┼─→  Ingress Controller (1 LB IP)  →  app1/app2/app3
  app3.example.com  ─┘     (NGINX/Traefik/etc.)
  example.com/api   ─┘
```

### Ingress Architecture

```
Internet
   │
   ▼
┌──────────────────────────────────────────────────────────┐
│  LoadBalancer Service (1 external IP)                    │
│  → nginx-ingress-controller Pod                          │
│                                                          │
│  Ingress Rules:                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │  host: app1.local  → Service: frontend (port 80) │   │
│  │  host: app2.local  → Service: backend  (port 80) │   │
│  │  host: *  path: /api  → Service: api   (port 80) │   │
│  │  host: *  path: /     → Service: web   (port 80) │   │
│  └──────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
```

### Ingress Controller vs Ingress Resource

```
Ingress Resource:
  - Là Kubernetes object (yaml)
  - Khai báo routing rules
  - Không làm gì nếu không có Controller

Ingress Controller:
  - Là Pod thực sự xử lý traffic
  - Reads Ingress resources và configures nginx/traefik/etc.
  - Phải được install riêng (không có sẵn trong K8s)
```

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Cài đặt NGINX Ingress Controller

**Cách 1: Minikube addon (dễ nhất)**
```bash
minikube addons enable ingress

# Kiểm tra
kubectl get pods -n ingress-nginx
# NAME                                        READY   STATUS      RESTARTS   AGE
# ingress-nginx-admission-create-xxxxx        0/1     Completed   0          2m
# ingress-nginx-admission-patch-xxxxx         0/1     Completed   0          2m
# ingress-nginx-controller-7dcdbcff84-xxxxx   1/1     Running     0          2m
```

**Cách 2: Helm (production-grade)**
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=2
```

**Cách 3: Manifest trực tiếp**
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
```

---

### Step 2: Deploy Frontend và Backend Apps

```bash
kubectl create namespace lab12

kubectl apply -f manifests/deployment-frontend.yaml -n lab12
kubectl apply -f manifests/deployment-backend.yaml -n lab12
kubectl apply -f manifests/service-frontend.yaml -n lab12
kubectl apply -f manifests/service-backend.yaml -n lab12
```

Kiểm tra:
```bash
kubectl get pods,svc -n lab12
# NAME                            READY   STATUS    RESTARTS
# pod/frontend-xxx-yyy            1/1     Running   0
# pod/backend-xxx-yyy             1/1     Running   0
#
# NAME               TYPE        CLUSTER-IP       PORT(S)   AGE
# service/backend    ClusterIP   10.96.100.101    80/TCP    1m
# service/frontend   ClusterIP   10.96.100.102    80/TCP    1m
```

---

### Step 3: Path-based Routing

```bash
kubectl apply -f manifests/ingress-path-based.yaml -n lab12
```

```bash
kubectl get ingress -n lab12
# NAME             CLASS   HOSTS   ADDRESS        PORTS   AGE
# ingress-path     nginx   *       192.168.49.2   80      30s

kubectl describe ingress ingress-path -n lab12
# Rules:
#   Host        Path  Backends
#   ----        ----  --------
#   *
#               /api(/|$)(.*)   backend:80
#               /               frontend:80
```

Test path-based routing:
```bash
# Lấy Ingress IP (Minikube)
INGRESS_IP=$(minikube ip)

# Test frontend (/)
curl http://$INGRESS_IP/
# <html>... Frontend App ...

# Test backend (/api)
curl http://$INGRESS_IP/api/
# {"message": "Backend API response"}

# Xem NGINX logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=20
```

---

### Step 4: Host-based Routing

Thêm entries vào `/etc/hosts` trên máy local:
```bash
INGRESS_IP=$(minikube ip)
echo "$INGRESS_IP app1.local app2.local" | sudo tee -a /etc/hosts
# hoặc nếu dùng minikube tunnel:
# echo "127.0.0.1 app1.local app2.local" | sudo tee -a /etc/hosts
```

```bash
kubectl apply -f manifests/ingress-host-based.yaml -n lab12
```

```bash
kubectl describe ingress ingress-host -n lab12
# Rules:
#   Host        Path  Backends
#   ----        ----  --------
#   app1.local
#               /     frontend:80
#   app2.local
#               /     backend:80
```

Test host-based routing:
```bash
curl http://app1.local/
# Frontend App

curl http://app2.local/
# Backend API

# Test với Host header (thay vì /etc/hosts)
curl -H "Host: app1.local" http://$INGRESS_IP/
curl -H "Host: app2.local" http://$INGRESS_IP/
```

---

### Step 5: TLS Termination

Tạo self-signed certificate:
```bash
# Tạo private key và certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/tls.key \
  -out /tmp/tls.crt \
  -subj "/CN=app1.local/O=lab12" \
  -addext "subjectAltName=DNS:app1.local,DNS:app2.local"

# Tạo TLS Secret
kubectl create secret tls lab12-tls \
  --cert=/tmp/tls.crt \
  --key=/tmp/tls.key \
  -n lab12

# Kiểm tra secret
kubectl get secret lab12-tls -n lab12
# NAME        TYPE                DATA   AGE
# lab12-tls   kubernetes.io/tls   2      10s
```

```bash
kubectl apply -f manifests/ingress-tls.yaml -n lab12
```

```bash
kubectl get ingress ingress-tls -n lab12
# NAME          CLASS   HOSTS        ADDRESS        PORTS     AGE
# ingress-tls   nginx   app1.local   192.168.49.2   80, 443   30s
```

Test TLS:
```bash
# Test HTTPS (skip cert verification vì self-signed)
curl -k https://app1.local/
# Frontend App

# Xem certificate info
echo | openssl s_client -connect app1.local:443 -servername app1.local 2>/dev/null | openssl x509 -text | grep -E "Subject:|Issuer:|Not"
# Subject: CN=app1.local, O=lab12
# Issuer: CN=app1.local, O=lab12
# Not Before: ...
# Not After: ...  (365 days from now)

# Test HTTP → HTTPS redirect (nếu có annotation)
curl -v http://app1.local/ 2>&1 | grep -E "< HTTP|Location"
# < HTTP/1.1 308 Permanent Redirect
# Location: https://app1.local/
```

---

### Step 6: Ingress Annotations

NGINX Ingress Controller hỗ trợ nhiều annotations:

```bash
# Xem annotations đang dùng trong ingress-tls
kubectl get ingress ingress-tls -n lab12 -o yaml | grep -A 20 annotations
```

Các annotations phổ biến:

```yaml
annotations:
  # Force HTTPS redirect
  nginx.ingress.kubernetes.io/ssl-redirect: "true"
  nginx.ingress.kubernetes.io/force-ssl-redirect: "true"

  # Rewrite path
  nginx.ingress.kubernetes.io/rewrite-target: /$2

  # Rate limiting
  nginx.ingress.kubernetes.io/limit-rps: "10"

  # Upload size
  nginx.ingress.kubernetes.io/proxy-body-size: "50m"

  # Timeouts
  nginx.ingress.kubernetes.io/proxy-connect-timeout: "30"
  nginx.ingress.kubernetes.io/proxy-read-timeout: "120"

  # CORS
  nginx.ingress.kubernetes.io/enable-cors: "true"
  nginx.ingress.kubernetes.io/cors-allow-origin: "*"

  # Custom NGINX config snippet
  nginx.ingress.kubernetes.io/configuration-snippet: |
    add_header X-Custom-Header "lab12";
```

Patch annotations lên ingress hiện có:
```bash
kubectl annotate ingress ingress-path \
  nginx.ingress.kubernetes.io/proxy-body-size=10m \
  -n lab12

kubectl annotate ingress ingress-path \
  nginx.ingress.kubernetes.io/configuration-snippet='add_header X-Lab "12";' \
  -n lab12
```

---

### Step 7: Rewrite Rules

Khi backend không biết về prefix trong URL:

```bash
# Scenario: Client request /api/users → Backend nhận /users

kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-rewrite
  namespace: lab12
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
    - host: app1.local
      http:
        paths:
          - path: /api(/|$)(.*)   # capture group $2
            pathType: ImplementationSpecific
            backend:
              service:
                name: backend
                port:
                  number: 80
EOF
```

```bash
# Test rewrite
curl -H "Host: app1.local" http://$INGRESS_IP/api/users
# → Backend nhận request tại /users (không phải /api/users)

curl -H "Host: app1.local" http://$INGRESS_IP/api/products/123
# → Backend nhận request tại /products/123
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
echo "=== Ingress Controller Status ==="
kubectl get pods -n ingress-nginx

echo ""
echo "=== All Ingress Resources ==="
kubectl get ingress -n lab12

echo ""
echo "=== Ingress Details ==="
kubectl describe ingress -n lab12

echo ""
echo "=== Test Connectivity ==="
INGRESS_IP=$(minikube ip)

echo "Testing path-based routing..."
curl -s -o /dev/null -w "Path / : HTTP %{http_code}\n" http://$INGRESS_IP/
curl -s -o /dev/null -w "Path /api : HTTP %{http_code}\n" http://$INGRESS_IP/api/

echo "Testing host-based routing..."
curl -s -o /dev/null -w "Host app1.local : HTTP %{http_code}\n" -H "Host: app1.local" http://$INGRESS_IP/
curl -s -o /dev/null -w "Host app2.local : HTTP %{http_code}\n" -H "Host: app2.local" http://$INGRESS_IP/

echo "Testing TLS..."
curl -sk -o /dev/null -w "HTTPS app1.local : HTTP %{http_code}\n" https://app1.local/
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xóa namespace lab12 và tất cả resources
kubectl delete namespace lab12

# Xóa /etc/hosts entries
sudo sed -i '' '/app1.local\|app2.local/d' /etc/hosts

# Nếu dùng Minikube addon
minikube addons disable ingress

# Nếu dùng Helm
# helm uninstall ingress-nginx -n ingress-nginx
```

---

## 💡 Tips & Gotchas

1. **IngressClass**: K8s 1.18+ yêu cầu `ingressClassName: nginx`. Không đặt sẽ bị ingress không match.

2. **PathType**: Có 3 loại:
   - `Exact`: match chính xác `/foo` (không match `/foo/`)
   - `Prefix`: prefix match `/foo` (match `/foo`, `/foo/`, `/foo/bar`)
   - `ImplementationSpecific`: tuỳ controller (NGINX dùng cho regex)

3. **Rewrite và capture group**: Khi dùng rewrite, path regex phải có capture group `(/|$)(.*)` và rewrite-target reference `$2`.

4. **TLS wildcard**: Để dùng `*.example.com`, cert phải có wildcard SAN.

5. **Multiple namespaces**: Ingress Controller mặc định watch tất cả namespaces. Có thể giới hạn bằng `--watch-namespace` flag.

6. **Backend protocol**: Nếu backend dùng HTTPS, thêm annotation:
   ```yaml
   nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
   ```

7. **Sticky sessions**: 
   ```yaml
   nginx.ingress.kubernetes.io/affinity: "cookie"
   nginx.ingress.kubernetes.io/session-cookie-name: "route"
   ```

---

## 📚 Tham khảo (References)

- [Ingress - Official Docs](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [NGINX Ingress Controller Docs](https://kubernetes.github.io/ingress-nginx/)
- [NGINX Ingress Annotations](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/)
- [Ingress Controllers List](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/)

---

## 🔗 Next Lab

👉 [Lab 13 — NetworkPolicy](../lab-13-network-policy/README.md)
