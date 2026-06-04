# Lab 08 — StatefulSet & Headless Service

## 🎯 Mục tiêu (Objectives)

Sau lab này bạn sẽ hiểu và làm được:
- Hiểu sự khác biệt cốt lõi giữa **StatefulSet** và **Deployment**
- Tạo **Headless Service** (`clusterIP: None`) để cấp DNS cho từng pod
- Hiểu **stable network identity**: mỗi pod có hostname cố định (`pod-0`, `pod-1`)
- Quan sát **ordered pod creation và deletion** (tạo tuần tự, xoá theo thứ tự ngược)
- Dùng **volumeClaimTemplates** để cấp PVC riêng cho từng pod
- Demo với **MySQL StatefulSet** thực tế

---

## 📋 Prerequisites

- Đã hoàn thành Lab 06 (Deployment), Lab 07 (DaemonSet)
- Cluster có **StorageClass** hỗ trợ dynamic provisioning
- Hiểu cơ bản về PersistentVolume và PersistentVolumeClaim

```bash
kubectl cluster-info
kubectl get nodes
# Kiểm tra StorageClass
kubectl get storageclass
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### StatefulSet vs Deployment

```
DEPLOYMENT (Stateless)          STATEFULSET (Stateful)
─────────────────────           ──────────────────────
pod-xyz123 (random name)        pod-0 (fixed name)
pod-abc456 (random name)        pod-1 (fixed name)
pod-def789 (random name)        pod-2 (fixed name)

↓ Xoá và tạo lại              ↓ Xoá và tạo lại

pod-new111 (mới, random)        pod-0 (VẪN tên này!)
pod-new222 (mới, random)        pod-1 (VẪN tên này!)
pod-new333 (mới, random)        pod-2 (VẪN tên này!)
```

| Tính năng | Deployment | StatefulSet |
|-----------|-----------|-------------|
| Pod identity | Random | Cố định (pod-0, pod-1...) |
| DNS hostname | Không ổn định | Ổn định |
| Tạo pod | Song song | Tuần tự (0→1→2) |
| Xoá pod | Song song | Ngược chiều (2→1→0) |
| Volume | Shared hoặc độc lập | Mỗi pod có PVC riêng |
| Update | Rolling (bất kỳ thứ tự) | Rolling (ngược chiều) |

### Headless Service và DNS

```
Normal Service (ClusterIP: 10.96.0.1):
  client → service-ip:80 → random pod (load balanced)

Headless Service (ClusterIP: None):
  client → DNS lookup → danh sách IPs của tất cả pods
  
  DNS records được tạo tự động:
  ┌──────────────────────────────────────────────────────────┐
  │ Service DNS:  nginx-headless.lab08.svc.cluster.local     │
  │               → trả về: [10.1.0.1, 10.1.0.2, 10.1.0.3] │
  │                                                          │
  │ Pod DNS:                                                 │
  │ nginx-0.nginx-headless.lab08.svc.cluster.local → 10.1.0.1│
  │ nginx-1.nginx-headless.lab08.svc.cluster.local → 10.1.0.2│
  │ nginx-2.nginx-headless.lab08.svc.cluster.local → 10.1.0.3│
  └──────────────────────────────────────────────────────────┘

  Pattern: {pod-name}.{service-name}.{namespace}.svc.cluster.local
```

### volumeClaimTemplates

Mỗi pod trong StatefulSet nhận một PVC **riêng biệt** và **cố định**:

```
StatefulSet: mysql (3 replicas)

mysql-0  ←→  PVC: data-mysql-0  ←→  PV (10Gi)
mysql-1  ←→  PVC: data-mysql-1  ←→  PV (10Gi)
mysql-2  ←→  PVC: data-mysql-2  ←→  PV (10Gi)

Nếu mysql-1 bị restart:
mysql-1 (mới) ←→ VẪN bind vào PVC: data-mysql-1 (dữ liệu được giữ lại!)
```

### Use Cases của StatefulSet

- **Databases**: MySQL, PostgreSQL, MongoDB
- **Message Queues**: Kafka, RabbitMQ
- **Distributed caches**: Redis Cluster
- **Coordination**: ZooKeeper, etcd
- **Distributed storage**: Cassandra, Elasticsearch

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Setup namespace

```bash
kubectl create namespace lab08
kubectl config set-context --current --namespace=lab08
```

### Step 2: Tạo Headless Service trước

**Quan trọng**: StatefulSet phải có Headless Service. Tạo Service trước khi tạo StatefulSet.

```bash
kubectl apply -f manifests/headless-service.yaml

# Kiểm tra Service
kubectl get service -n lab08
# NAME              TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
# nginx-headless    ClusterIP   None         <none>        80/TCP    5s
# ↑ CLUSTER-IP là None = Headless Service
```

### Step 3: Tạo StatefulSet Nginx

```bash
kubectl apply -f manifests/statefulset-nginx.yaml
```

**Quan sát pods được tạo TUẦN TỰ** (quan trọng!):
```bash
kubectl get pods -n lab08 -w
# nginx-0   0/1   Pending           0   0s    ← Tạo nginx-0 trước
# nginx-0   0/1   ContainerCreating 0   1s
# nginx-0   1/1   Running           0   5s    ← nginx-0 Ready
# nginx-1   0/1   Pending           0   6s    ← Chỉ sau khi nginx-0 Ready
# nginx-1   0/1   ContainerCreating 0   7s
# nginx-1   1/1   Running           0   12s   ← nginx-1 Ready
# nginx-2   0/1   Pending           0   13s   ← Chỉ sau khi nginx-1 Ready
# nginx-2   1/1   Running           0   20s
```

### Step 4: Kiểm tra DNS resolution cho từng pod

Chạy một pod debug để test DNS:
```bash
kubectl run dns-test --image=busybox:1.35 --restart=Never -n lab08 -- sleep 3600
kubectl exec dns-test -n lab08 -- sh -c "
echo '=== Lookup Headless Service ===' && \
nslookup nginx-headless.lab08.svc.cluster.local && \
echo '=== Lookup Pod DNS ===' && \
nslookup nginx-0.nginx-headless.lab08.svc.cluster.local && \
nslookup nginx-1.nginx-headless.lab08.svc.cluster.local && \
nslookup nginx-2.nginx-headless.lab08.svc.cluster.local
"
```

**Output mong đợi:**
```
=== Lookup Headless Service ===
Server:    10.96.0.10
Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local

Name:      nginx-headless.lab08.svc.cluster.local
Address 1: 10.1.0.10 nginx-0.nginx-headless.lab08.svc.cluster.local
Address 2: 10.1.0.11 nginx-1.nginx-headless.lab08.svc.cluster.local
Address 3: 10.1.0.12 nginx-2.nginx-headless.lab08.svc.cluster.local

=== Lookup Pod DNS ===
Name:      nginx-0.nginx-headless.lab08.svc.cluster.local
Address 1: 10.1.0.10
```

### Step 5: Kiểm tra stable identity sau khi xoá pod

```bash
# Xoá nginx-1
kubectl delete pod nginx-1 -n lab08

# Watch: nginx-1 sẽ được recreate với TÊN nginx-1 (không phải tên random)
kubectl get pods -n lab08 -w
```

```bash
# Kiểm tra nginx-1 vẫn có cùng DNS entry
kubectl exec dns-test -n lab08 -- nslookup nginx-1.nginx-headless.lab08.svc.cluster.local
```

### Step 6: Kiểm tra PVC riêng cho từng pod

```bash
# Xem PVCs được tạo bởi StatefulSet
kubectl get pvc -n lab08
# NAME              STATUS   VOLUME                    CAPACITY   ACCESS MODES   STORAGECLASS
# www-nginx-0       Bound    pvc-xxx...                1Gi        RWO            standard
# www-nginx-1       Bound    pvc-yyy...                1Gi        RWO            standard
# www-nginx-2       Bound    pvc-zzz...                1Gi        RWO            standard
```

Ghi dữ liệu vào PVC của nginx-0:
```bash
kubectl exec nginx-0 -n lab08 -- sh -c 'echo "Hello from nginx-0 StatefulSet $(date)" > /usr/share/nginx/html/index.html'

# Xoá pod nginx-0
kubectl delete pod nginx-0 -n lab08

# Chờ pod recreate
kubectl wait pod/nginx-0 -n lab08 --for=condition=Ready --timeout=60s

# Kiểm tra dữ liệu vẫn còn sau khi pod restart!
kubectl exec nginx-0 -n lab08 -- cat /usr/share/nginx/html/index.html
# Hello from nginx-0 StatefulSet ... ← Dữ liệu được preserved!
```

### Step 7: Quan sát ordered deletion (xoá theo thứ tự ngược)

```bash
# Scale down từ 3 → 0 và quan sát thứ tự xoá
kubectl scale statefulset nginx -n lab08 --replicas=0

# Watch: nginx-2 bị xoá trước, rồi nginx-1, cuối cùng nginx-0
kubectl get pods -n lab08 -w
```

### Step 8: Deploy MySQL StatefulSet

```bash
kubectl apply -f manifests/statefulset-mysql.yaml

# Chờ MySQL khởi động
kubectl rollout status statefulset/mysql -n lab08

# Kiểm tra
kubectl get statefulset mysql -n lab08
kubectl get pods -n lab08 -l app=mysql
kubectl get pvc -n lab08
```

Kết nối vào MySQL:
```bash
kubectl exec -it mysql-0 -n lab08 -- mysql -u root -proot123 -e "SHOW DATABASES;"

# Tạo database và table
kubectl exec mysql-0 -n lab08 -- mysql -u root -proot123 -e "
CREATE DATABASE IF NOT EXISTS testdb;
USE testdb;
CREATE TABLE IF NOT EXISTS users (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(100), created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
INSERT INTO users (name) VALUES ('Alice'), ('Bob'), ('Charlie');
SELECT * FROM users;
"
```

Xoá và restart pod MySQL — dữ liệu vẫn còn:
```bash
kubectl delete pod mysql-0 -n lab08
kubectl wait pod/mysql-0 -n lab08 --for=condition=Ready --timeout=120s
kubectl exec mysql-0 -n lab08 -- mysql -u root -proot123 -e "SELECT * FROM testdb.users;"
# Alice, Bob, Charlie vẫn còn!
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# 1. Kiểm tra StatefulSets
kubectl get statefulset -n lab08

# 2. Kiểm tra pod identity (phải là nginx-0, nginx-1, nginx-2)
kubectl get pods -n lab08 -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP

# 3. Kiểm tra Headless Service
kubectl get svc nginx-headless -n lab08 -o jsonpath='{.spec.clusterIP}'
# Phải trả về: None

# 4. Kiểm tra PVCs
kubectl get pvc -n lab08

# 5. Kiểm tra DNS resolution
kubectl exec dns-test -n lab08 -- nslookup nginx-0.nginx-headless.lab08.svc.cluster.local

# 6. Kiểm tra tất cả resources
kubectl get all -n lab08
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xoá StatefulSets (không xoá PVCs!)
kubectl delete statefulset nginx mysql -n lab08

# Xoá PVCs (xoá dữ liệu!)
kubectl delete pvc -n lab08 --all

# Xoá còn lại
kubectl delete -f manifests/ -n lab08

# Xoá namespace
kubectl delete namespace lab08

kubectl config set-context --current --namespace=default
```

---

## 💡 Tips & Gotchas

1. **PVCs không bị xoá khi StatefulSet bị xoá**: Đây là behavior cố ý để tránh mất dữ liệu. Phải xoá PVC thủ công.

2. **Headless Service phải được tạo TRƯỚC StatefulSet**: StatefulSet tham chiếu `serviceName` và cần Service tồn tại.

3. **Pod phải Ready trước khi pod tiếp theo được tạo**: Nếu pod không Ready (e.g., liveness probe fail), StatefulSet sẽ bị stuck.

4. **`updateStrategy: RollingUpdate` với `partition`**: Cho phép canary update:
   ```yaml
   updateStrategy:
     type: RollingUpdate
     rollingUpdate:
       partition: 2  # Chỉ update pod có ordinal >= 2
   ```

5. **Không dùng StatefulSet cho stateless apps**: StatefulSet có overhead cao hơn. Chỉ dùng khi thực sự cần stable identity hoặc persistent storage per-pod.

6. **`podManagementPolicy: Parallel`**: Nếu không cần ordered creation:
   ```yaml
   spec:
     podManagementPolicy: Parallel  # Tạo/xoá tất cả pods cùng lúc
   ```

---

## 📚 Tham khảo (References)

- [StatefulSets | Kubernetes Docs](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [Headless Services](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services)
- [Running a Replicated Stateful Application](https://kubernetes.io/docs/tasks/run-application/run-replicated-stateful-application/)

---

## 🔗 Next Lab

➡️ [Lab 09 — Job & CronJob](../lab-09-job-cronjob/README.md)
