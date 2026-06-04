# Lab 15 — ConfigMap

## 🎯 Mục tiêu (Objectives)

Sau khi hoàn thành lab này, bạn sẽ có thể:

- Tạo ConfigMap từ nhiều nguồn: literal values, file, directory
- Inject ConfigMap vào Pod dưới dạng biến môi trường (env var) với `valueFrom.configMapKeyRef`
- Inject toàn bộ keys của ConfigMap với `envFrom`
- Mount ConfigMap như Volume (mỗi key là một file riêng)
- Hiểu cách Pod reload config khi ConfigMap được cập nhật
- Sử dụng Immutable ConfigMap để tăng performance

---

## 📋 Prerequisites

- Đã hoàn thành Lab 14 (Probes & Lifecycle)
- `kubectl` đã cấu hình kết nối tới cluster
- Cluster đang chạy (Minikube, kind, hoặc real cluster)

```bash
kubectl cluster-info
kubectl get nodes
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### ConfigMap là gì?

**ConfigMap** là một Kubernetes object dùng để lưu trữ dữ liệu cấu hình dạng **key-value** (non-secret). Tách biệt config khỏi container image giúp ứng dụng portable hơn.

```
┌─────────────────────────────────────────────────────────┐
│                      ConfigMap                          │
│                                                         │
│  data:                                                  │
│    APP_ENV: "production"          ◄── string value      │
│    APP_PORT: "8080"               ◄── string value      │
│    nginx.conf: |                  ◄── multi-line file   │
│      server {                                           │
│        listen 80;                                       │
│      }                                                  │
└──────────────┬──────────────────────────────────────────┘
               │
       ┌───────┴──────────┐
       │                  │
       ▼                  ▼
  Env Variables      Volume Mount
  (key=value)        (file per key)
```

### Các cách inject ConfigMap vào Pod

| Phương thức | Cách dùng | Reload khi update? |
|---|---|---|
| `env.valueFrom.configMapKeyRef` | Inject 1 key cụ thể | ❌ Không (cần restart Pod) |
| `envFrom.configMapRef` | Inject tất cả keys | ❌ Không (cần restart Pod) |
| `volumes` + `volumeMounts` | Mount như filesystem | ✅ Có (sau ~60s) |

---

## 🛠️ Thực hành (Hands-on)

### Bước 1: Tạo Namespace

```bash
kubectl create namespace lab15
kubectl config set-context --current --namespace=lab15
```

### Bước 2: Tạo ConfigMap từ literal values

Cách nhanh nhất để tạo ConfigMap:

```bash
kubectl create configmap app-settings \
  --from-literal=APP_ENV=production \
  --from-literal=APP_PORT=8080 \
  --from-literal=APP_DEBUG=false \
  --from-literal=LOG_LEVEL=info \
  -n lab15

# Kiểm tra
kubectl get configmap app-settings -n lab15
kubectl describe configmap app-settings -n lab15
```

Expected output:
```
Name:         app-settings
Namespace:    lab15
Labels:       <none>
Annotations:  <none>

Data
====
APP_DEBUG:
----
false
APP_ENV:
----
production
APP_PORT:
----
8080
LOG_LEVEL:
----
info
```

```bash
# Xem dưới dạng YAML
kubectl get configmap app-settings -n lab15 -o yaml
```

### Bước 3: Tạo ConfigMap từ file

Tạo một file config trước:

```bash
# Tạo file application.properties
cat > /tmp/application.properties << 'EOF'
spring.datasource.url=jdbc:postgresql://postgres:5432/mydb
spring.datasource.driver-class-name=org.postgresql.Driver
spring.jpa.hibernate.ddl-auto=validate
spring.cache.type=redis
server.port=8080
management.endpoints.web.exposure.include=health,info,metrics
EOF

# Tạo ConfigMap từ file
kubectl create configmap app-properties \
  --from-file=application.properties=/tmp/application.properties \
  -n lab15

# Kiểm tra - key là tên file
kubectl get configmap app-properties -n lab15 -o yaml
```

### Bước 4: Tạo ConfigMap từ directory

```bash
# Tạo directory với nhiều config files
mkdir -p /tmp/configs
cat > /tmp/configs/database.conf << 'EOF'
host=postgres-service
port=5432
name=myapp_db
pool_size=10
EOF

cat > /tmp/configs/cache.conf << 'EOF'
host=redis-service
port=6379
ttl=3600
EOF

cat > /tmp/configs/feature-flags.json << 'EOF'
{
  "newUI": true,
  "betaFeature": false,
  "darkMode": true
}
EOF

# Tạo ConfigMap từ toàn bộ directory
kubectl create configmap app-configs \
  --from-file=/tmp/configs/ \
  -n lab15

# Mỗi file trở thành một key
kubectl describe configmap app-configs -n lab15
```

### Bước 5: Apply ConfigMap từ YAML manifest

```bash
kubectl apply -f manifests/configmap-app-config.yaml
kubectl apply -f manifests/configmap-nginx-conf.yaml
```

### Bước 6: Inject ConfigMap vào Pod - Env Variables

```bash
# Apply Pod sử dụng env vars từ ConfigMap
kubectl apply -f manifests/pod-env-from-configmap.yaml

# Xem Pod status
kubectl get pod pod-env-demo -n lab15 -w

# Khi Pod Running, kiểm tra env vars
kubectl exec pod-env-demo -n lab15 -- env | grep -E "APP_|LOG_"
```

Expected output:
```
APP_ENV=production
APP_PORT=8080
APP_DEBUG=false
LOG_LEVEL=info
DB_HOST=postgres-service
DB_PORT=5432
```

```bash
# Verify với envFrom (tất cả keys)
kubectl exec pod-env-demo -n lab15 -- printenv | sort
```

### Bước 7: Mount ConfigMap như Volume

```bash
kubectl apply -f manifests/pod-volume-from-configmap.yaml

# Chờ Pod running
kubectl wait --for=condition=Ready pod/pod-volume-demo -n lab15 --timeout=60s

# Kiểm tra files được mount
kubectl exec pod-volume-demo -n lab15 -- ls -la /etc/config/

# Đọc nội dung file (mỗi key = 1 file)
kubectl exec pod-volume-demo -n lab15 -- cat /etc/config/APP_ENV
kubectl exec pod-volume-demo -n lab15 -- cat /etc/config/LOG_LEVEL

# Kiểm tra nginx config được mount
kubectl exec pod-volume-demo -n lab15 -- ls /etc/nginx/conf.d/
kubectl exec pod-volume-demo -n lab15 -- cat /etc/nginx/conf.d/default.conf
```

### Bước 8: Deploy ứng dụng với ConfigMap

```bash
kubectl apply -f manifests/deployment-with-config.yaml

kubectl get deployment webapp -n lab15
kubectl get pods -n lab15 -l app=webapp
```

### Bước 9: Update ConfigMap và quan sát reload

```bash
# Cập nhật ConfigMap
kubectl edit configmap configmap-app-config -n lab15
# Thay đổi LOG_LEVEL từ info sang debug

# Hoặc dùng patch
kubectl patch configmap configmap-app-config -n lab15 \
  --type merge \
  -p '{"data": {"LOG_LEVEL": "debug"}}'

# Với env var: KHÔNG tự reload, cần restart Pod
kubectl rollout restart deployment webapp -n lab15

# Với volume mount: tự reload sau khoảng 60s (kubelet sync period)
# Theo dõi thay đổi file
kubectl exec pod-volume-demo -n lab15 -- watch -n 5 cat /etc/config/LOG_LEVEL
```

⚠️ **Quan trọng**: Khi ConfigMap được mount dưới dạng Volume, Kubernetes sẽ tự động cập nhật nội dung file sau khoảng `kubelet.configMapAndSecretChangeDetectionStrategy` (mặc định ~60 giây). Nhưng **ứng dụng phải tự xử lý việc đọc lại config** (watch file changes hoặc signal).

### Bước 10: Immutable ConfigMap

```bash
# Tạo immutable ConfigMap (Kubernetes 1.21+)
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: immutable-config
  namespace: lab15
immutable: true
data:
  VERSION: "1.0.0"
  BUILD_DATE: "2024-01-15"
EOF

# Thử update - sẽ bị lỗi
kubectl patch configmap immutable-config -n lab15 \
  --type merge \
  -p '{"data": {"VERSION": "2.0.0"}}'
# Error: configmap "immutable-config" is immutable

# Để thay đổi, phải delete và recreate
kubectl delete configmap immutable-config -n lab15
```

**Lợi ích của Immutable ConfigMap:**
- Kubernetes không cần watch changes → giảm load trên API server
- Prevent accidental updates
- Nên dùng với phiên bản hóa: `configmap-v1`, `configmap-v2`

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# 1. Liệt kê tất cả ConfigMaps
kubectl get configmaps -n lab15

# 2. Verify env vars trong Pod
kubectl exec pod-env-demo -n lab15 -- env | grep APP_ENV
# APP_ENV=production

# 3. Verify volume mount
kubectl exec pod-volume-demo -n lab15 -- cat /etc/config/APP_ENV
# production

# 4. Verify nginx config
kubectl exec pod-volume-demo -n lab15 -- nginx -t
# nginx: the configuration file /etc/nginx/nginx.conf syntax is ok

# 5. Kiểm tra Deployment
kubectl rollout status deployment/webapp -n lab15
# deployment "webapp" successfully rolled out

# 6. Describe pod để xem ConfigMap references
kubectl describe pod -n lab15 -l app=webapp | grep -A5 "Environment"
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xóa tất cả resources trong namespace
kubectl delete namespace lab15

# Hoặc xóa từng resource
kubectl delete -f manifests/ -n lab15
kubectl delete configmap app-settings app-properties app-configs -n lab15

# Reset namespace context về default
kubectl config set-context --current --namespace=default
```

---

## 💡 Tips & Gotchas

### ❌ Lỗi thường gặp

1. **ConfigMap key không tồn tại**
   ```
   Error: couldn't find key MY_KEY in ConfigMap namespace/my-config
   ```
   → Kiểm tra spelling, ConfigMap phải tồn tại trước khi Pod start

2. **Env vars không reload sau khi update ConfigMap**
   → Env vars được inject lúc Pod start, KHÔNG reload. Phải restart Pod.

3. **Volume mount override cả directory**
   ```yaml
   # Sai: sẽ xóa hết files trong /etc/nginx/
   mountPath: /etc/nginx
   
   # Đúng: chỉ mount vào subdirectory
   mountPath: /etc/nginx/conf.d
   
   # Hoặc dùng subPath để mount file đơn lẻ
   mountPath: /etc/nginx/nginx.conf
   subPath: nginx.conf
   ```

4. **Binary data** trong ConfigMap: dùng `binaryData` field thay vì `data`

### ✅ Best Practices

- Đặt tên ConfigMap có ý nghĩa: `<app>-<env>-config`
- Dùng `immutable: true` cho configs không thay đổi → tăng hiệu năng
- Không lưu sensitive data (passwords, tokens) trong ConfigMap → dùng Secret
- Versioning ConfigMap: `app-config-v1`, `app-config-v2`
- Validate config files trước khi update bằng dry-run:
  ```bash
  kubectl apply -f manifests/configmap-app-config.yaml --dry-run=server
  ```

---

## 📚 Tham khảo (References)

- [Official Docs: ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Configure a Pod to Use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/)
- [Immutable ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/#configmap-immutable)

---

## 🔗 Next Lab

➡️ **[Lab 16 — Secret](../lab-16-secret/README.md)**: Quản lý sensitive data (passwords, tokens, certificates) với Kubernetes Secrets.
