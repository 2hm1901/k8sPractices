# Lab 19 — Resource Requests & Limits

## 🎯 Mục tiêu (Objectives)

Sau khi hoàn thành lab này, bạn sẽ có thể:

- Hiểu đơn vị CPU (millicores) và Memory (Mi/Gi)
- Phân biệt Requests (scheduler hint) và Limits (enforced cap)
- Phân loại và tạo Pods với 3 QoS Classes: Guaranteed, Burstable, BestEffort
- Mô phỏng OOMKilled và CPU throttling scenarios
- Cấu hình LimitRange để đặt defaults cho Namespace
- Cấu hình ResourceQuota để giới hạn tổng resources cho Namespace
- Dùng `kubectl top` để monitor resource usage

---

## 📋 Prerequisites

- Đã hoàn thành Lab 18 (StorageClass)
- `kubectl` đã cấu hình kết nối tới cluster
- metrics-server đã được cài đặt (để dùng `kubectl top`)
- Hiểu cơ bản về CPU và Memory

```bash
# Kiểm tra metrics-server
kubectl top nodes
# Nếu lỗi: install metrics-server
minikube addons enable metrics-server   # Minikube
# hoặc
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Đơn vị Resources

```
CPU:
  1 CPU  = 1000m (millicores)  = 1 vCPU/Core/Hyperthread
  500m   = 0.5 CPU             = half a core
  100m   = 0.1 CPU             = 1/10 of a core
  
  Ví dụ: "250m" = một phần tư CPU

Memory:
  Ki = Kibibyte  = 1024 bytes
  Mi = Mebibyte  = 1024 Ki
  Gi = Gibibyte  = 1024 Mi
  
  K  = Kilobyte  = 1000 bytes
  M  = Megabyte  = 1000 K
  G  = Gigabyte  = 1000 M
  
  128Mi ≈ 134MB (dùng Mi/Gi trong K8s cho rõ ràng)
```

### Requests vs Limits

```
REQUESTS (Yêu cầu tối thiểu):
  - Kubernetes scheduler dùng để quyết định node nào đủ tài nguyên
  - Container được đảm bảo có ít nhất amount này
  - Node không bị overcommit về requests

LIMITS (Giới hạn tối đa):
  - Container KHÔNG thể vượt quá amount này
  - CPU throttled nếu vượt limit (không bị kill)
  - Memory killed (OOMKilled) nếu vượt limit
  
  ┌──────────────────────────────────────────┐
  │  Node: 4 CPU, 8Gi Memory                │
  │                                          │
  │  Pod A: request=500m, limit=1000m        │
  │  Pod B: request=500m, limit=2000m        │
  │  Pod C: request=500m, limit=1000m        │
  │                                          │
  │  Total requests: 1500m ≤ 4000m ✓        │
  │  Total limits: 4000m can exceed node ⚠️  │
  └──────────────────────────────────────────┘
```

### QoS Classes (Quality of Service)

```
┌─────────────────────────────────────────────────────────┐
│  GUARANTEED (Ưu tiên cao nhất, ít bị evict nhất)        │
│  Điều kiện: requests == limits cho TẤT CẢ containers    │
│  resources:                                             │
│    requests: {cpu: "500m", memory: "256Mi"}             │
│    limits:   {cpu: "500m", memory: "256Mi"}  ← EQUAL    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  BURSTABLE (Trung bình)                                 │
│  Điều kiện: có requests/limits nhưng KHÔNG bằng nhau   │
│  resources:                                             │
│    requests: {cpu: "250m", memory: "128Mi"}             │
│    limits:   {cpu: "1000m", memory: "512Mi"} ← DIFFER   │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  BESTEFFORT (Ưu tiên thấp nhất, evict đầu tiên)         │
│  Điều kiện: KHÔNG có requests NÀO lẫn limits            │
│  resources: {}  ← Empty!                                │
└─────────────────────────────────────────────────────────┘

Eviction order: BestEffort → Burstable → Guaranteed
```

---

## 🛠️ Thực hành (Hands-on)

### Bước 1: Tạo Namespace và cài metrics-server

```bash
kubectl create namespace lab19
kubectl config set-context --current --namespace=lab19

# Cài metrics-server nếu chưa có
minikube addons enable metrics-server

# Chờ metrics-server sẵn sàng (1-2 phút)
kubectl wait --for=condition=Ready pod \
  -l k8s-app=metrics-server \
  -n kube-system --timeout=120s

# Test
kubectl top nodes
```

### Bước 2: Deploy QoS Class - Guaranteed

```bash
kubectl apply -f manifests/pod-guaranteed-qos.yaml

kubectl get pod pod-guaranteed -n lab19

# Verify QoS class
kubectl get pod pod-guaranteed -n lab19 \
  -o jsonpath='{.status.qosClass}'
# Guaranteed

kubectl describe pod pod-guaranteed -n lab19 | grep -A10 "QoS Class"
```

### Bước 3: Deploy QoS Class - Burstable

```bash
kubectl apply -f manifests/pod-burstable-qos.yaml

kubectl get pod pod-burstable -n lab19

# Verify QoS class
kubectl get pod pod-burstable -n lab19 \
  -o jsonpath='{.status.qosClass}'
# Burstable
```

### Bước 4: Deploy QoS Class - BestEffort

```bash
kubectl apply -f manifests/pod-besteffort-qos.yaml

kubectl get pod pod-besteffort -n lab19

# Verify QoS class
kubectl get pod pod-besteffort -n lab19 \
  -o jsonpath='{.status.qosClass}'
# BestEffort
```

### Bước 5: So sánh 3 QoS Classes

```bash
# Xem tất cả cùng lúc
kubectl get pods -n lab19 -o custom-columns=\
'NAME:.metadata.name,QOS:.status.qosClass,STATUS:.status.phase'
```

Expected:
```
NAME               QOS           STATUS
pod-besteffort     BestEffort    Running
pod-burstable      Burstable     Running
pod-guaranteed     Guaranteed    Running
```

```bash
# Xem resource requests của mỗi Pod
kubectl get pod pod-guaranteed -n lab19 \
  -o jsonpath='{.spec.containers[*].resources}' | python3 -m json.tool

kubectl get pod pod-burstable -n lab19 \
  -o jsonpath='{.spec.containers[*].resources}' | python3 -m json.tool
```

### Bước 6: OOMKilled Simulation

```bash
# Tạo Pod với memory limit thấp và stress memory
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: pod-oom-test
  namespace: lab19
spec:
  containers:
  - name: memory-hog
    image: polinux/stress:latest
    # Consume 150Mi memory nhưng limit chỉ 100Mi → OOMKilled!
    command: ["stress"]
    args: ["--vm", "1", "--vm-bytes", "150M", "--vm-hang", "1"]
    resources:
      requests:
        memory: "50Mi"
        cpu: "100m"
      limits:
        memory: "100Mi"  # Only 100Mi allowed!
        cpu: "500m"
  restartPolicy: OnFailure
EOF

# Theo dõi Pod - sẽ OOMKilled rất nhanh
kubectl get pod pod-oom-test -n lab19 -w
```

Expected:
```
NAME           READY   STATUS      RESTARTS   AGE
pod-oom-test   0/1     OOMKilled   0          3s
pod-oom-test   0/1     OOMKilled   1          10s
pod-oom-test   0/1     CrashLoopBackOff  2   20s
```

```bash
# Xem lý do fail
kubectl describe pod pod-oom-test -n lab19 | grep -A5 "Last State"
# Last State: Terminated
#   Reason: OOMKilled
#   Exit Code: 137

# Xóa Pod test
kubectl delete pod pod-oom-test -n lab19
```

### Bước 7: CPU Throttling Demo

```bash
# CPU throttling khác OOMKill - không kill, chỉ làm chậm
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: pod-cpu-throttle
  namespace: lab19
spec:
  containers:
  - name: cpu-hog
    image: polinux/stress:latest
    command: ["stress"]
    args: ["--cpu", "4", "--timeout", "60s"]  # Stress 4 CPUs
    resources:
      requests:
        cpu: "100m"
      limits:
        cpu: "200m"  # Chỉ được dùng 200m (0.2 CPU) dù stress 4 CPUs
EOF

# Theo dõi - Pod sẽ Running nhưng CPU bị throttle
kubectl get pod pod-cpu-throttle -n lab19 -w

# Xem actual CPU usage
kubectl top pod pod-cpu-throttle -n lab19
# CPU(cores): sẽ không vượt 200m (limit)
```

### Bước 8: LimitRange - Namespace Defaults

```bash
kubectl apply -f manifests/limitrange-dev.yaml

kubectl describe limitrange dev-limits -n lab19
```

Expected:
```
Name:       dev-limits
Namespace:  lab19
Type        Resource  Min   Max    Default Request  Default Limit  Max Limit/Request Ratio
----        --------  ---   ---    ---------------  -------------  -----------------------
Container   cpu       50m   2      100m             500m           10
Container   memory    64Mi  1Gi    128Mi            256Mi          4
Pod         cpu       100m  4      -                -              -
Pod         memory    128Mi 2Gi    -                -              -
```

```bash
# Tạo Pod KHÔNG specify resources → LimitRange áp dụng defaults
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: pod-no-resources
  namespace: lab19
spec:
  containers:
  - name: app
    image: nginx:1.25-alpine
    # Không có resources block!
EOF

# LimitRange tự động thêm defaults
kubectl get pod pod-no-resources -n lab19 \
  -o jsonpath='{.spec.containers[0].resources}' | python3 -m json.tool
# {"limits": {"cpu": "500m", "memory": "256Mi"},
#  "requests": {"cpu": "100m", "memory": "128Mi"}}
```

```bash
# Thử vượt quá max limit - sẽ bị reject
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: pod-exceed-limit
  namespace: lab19
spec:
  containers:
  - name: app
    image: nginx:1.25-alpine
    resources:
      limits:
        cpu: "4"  # Max là 2 CPU → sẽ bị reject!
        memory: "1Gi"
EOF
# Error: pods "pod-exceed-limit" is forbidden: maximum cpu usage per Container is 2, but limit is 4.
```

### Bước 9: ResourceQuota - Namespace Total Limits

```bash
kubectl apply -f manifests/resourcequota-dev.yaml

kubectl describe resourcequota dev-quota -n lab19
```

Expected:
```
Name:                   dev-quota
Namespace:              lab19
Resource                Used   Hard
--------                ----   ----
configmaps              0      10
limits.cpu              750m   8
limits.memory           640Mi  4Gi
persistentvolumeclaims  0      5
pods                    3      20
requests.cpu            300m   4
requests.memory         320Mi  2Gi
secrets                 1      10
services                0      10
services.loadbalancers  0      2
services.nodeports      0      5
```

```bash
# Thử vượt quota - deploy nhiều Pods
kubectl apply -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: heavy-app
  namespace: lab19
spec:
  replicas: 100  # Sẽ bị giới hạn bởi quota pods: 20
  selector:
    matchLabels:
      app: heavy
  template:
    metadata:
      labels:
        app: heavy
    spec:
      containers:
      - name: app
        image: nginx:1.25-alpine
        resources:
          requests:
            cpu: "500m"
            memory: "256Mi"
          limits:
            cpu: "1"
            memory: "512Mi"
EOF

# Kiểm tra - chỉ tạo được bao nhiêu Pods?
kubectl get deployment heavy-app -n lab19
kubectl get pods -n lab19 -l app=heavy | wc -l

kubectl describe quota dev-quota -n lab19
# Xem Used vs Hard để biết quota đã dùng bao nhiêu
```

### Bước 10: Deploy ứng dụng thực tế với resources đầy đủ

```bash
kubectl apply -f manifests/deployment-with-resources.yaml

kubectl get deployment webapp -n lab19
kubectl get pods -n lab19 -l app=webapp

# Monitor resources
kubectl top pods -n lab19 -l app=webapp
kubectl top pods -n lab19 --sort-by=memory
kubectl top pods -n lab19 --sort-by=cpu
```

### Bước 11: kubectl top - Resource Monitoring

```bash
# Monitor nodes
kubectl top nodes
kubectl top nodes --sort-by=cpu
kubectl top nodes --sort-by=memory

# Monitor pods
kubectl top pods -n lab19
kubectl top pods -n lab19 --containers  # Hiện per-container
kubectl top pods --all-namespaces

# Kiểm tra xem resources được request bao nhiêu so với actual usage
kubectl top pods -n lab19
# Nếu usage >> requests → cần tăng requests
# Nếu usage << limits → có thể giảm limits để tiết kiệm
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# 1. Verify QoS Classes
for pod in pod-guaranteed pod-burstable pod-besteffort; do
  echo -n "$pod: "
  kubectl get pod $pod -n lab19 -o jsonpath='{.status.qosClass}'
  echo
done

# 2. Verify LimitRange defaults được apply
kubectl get pod pod-no-resources -n lab19 \
  -o jsonpath='{.spec.containers[0].resources.limits.cpu}'
# 500m (default limit)

# 3. Verify ResourceQuota
kubectl describe resourcequota dev-quota -n lab19

# 4. Verify Node resource usage
kubectl top nodes

# 5. Verify Pod resource usage
kubectl top pods -n lab19

# 6. Verify OOMKilled behavior
kubectl describe pod pod-oom-test -n lab19 2>/dev/null | grep "OOMKilled" || echo "Pod cleaned up"
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xóa Deployment test
kubectl delete deployment heavy-app webapp -n lab19 --ignore-not-found

# Xóa Pods test
kubectl delete pod pod-guaranteed pod-burstable pod-besteffort \
  pod-no-resources pod-cpu-throttle pod-oom-test -n lab19 --ignore-not-found

# Xóa LimitRange và ResourceQuota
kubectl delete limitrange dev-limits -n lab19 --ignore-not-found
kubectl delete resourcequota dev-quota -n lab19 --ignore-not-found

# Xóa namespace
kubectl delete namespace lab19

# Reset namespace context
kubectl config set-context --current --namespace=default
```

---

## 💡 Tips & Gotchas

### ❌ Lỗi thường gặp

1. **Pod Pending vì không đủ resources**
   ```
   0/3 nodes are available: 3 Insufficient memory
   ```
   → Giảm requests hoặc thêm nodes

2. **OOMKilled liên tục (CrashLoopBackOff)**
   ```bash
   kubectl describe pod <name> | grep -A3 "Last State"
   # Reason: OOMKilled
   ```
   → Tăng memory limit hoặc tối ưu ứng dụng

3. **Pod bị evict khi node áp lực**
   ```
   Evicted: The node was low on resource: memory
   ```
   → BestEffort bị evict trước, nâng lên Guaranteed nếu cần ổn định

4. **LimitRange yêu cầu resources khi tạo Pod**
   ```
   Error: pods "my-pod" is forbidden: [minimum cpu usage per Container is 50m]
   ```
   → Thêm resources block vào Pod spec, hoặc xem LimitRange min values

5. **ResourceQuota exceeded**
   ```
   Error: exceeded quota: dev-quota, requested: pods=1, used: pods=20, limited: pods=20
   ```
   → Tăng quota hoặc xóa Pods không cần thiết

### ✅ Best Practices

**Luôn đặt Requests và Limits:**
```yaml
resources:
  requests:
    cpu: "100m"      # Đủ để chạy bình thường
    memory: "128Mi"
  limits:
    cpu: "500m"      # Cho phép burst
    memory: "256Mi"  # Không OOMKill production apps
```

**Right-sizing resources:**
```bash
# Dùng kubectl top để xem actual usage
kubectl top pods -n <ns> --containers

# Rule of thumb:
# requests = average usage
# limits = peak usage * 1.5
```

**QoS Strategy:**
- Production databases: **Guaranteed** (ổn định nhất)
- Web APIs: **Burstable** (balance giữa performance và cost)
- Batch jobs: **BestEffort** (nếu có thể bị preempted)

**Vertical Pod Autoscaler (VPA):**
```bash
# VPA tự động điều chỉnh requests/limits dựa trên actual usage
# https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler
```

**Horizontal Pod Autoscaler (HPA) + Requests:**
```bash
# HPA scale dựa trên actual usage / requests
# Nếu requests quá thấp → HPA scale sớm hơn cần thiết
kubectl autoscale deployment webapp \
  --cpu-percent=70 \
  --min=2 --max=10 \
  -n lab19
```

---

## 📚 Tham khảo (References)

- [Official Docs: Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [QoS Classes](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/)
- [LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/)
- [ResourceQuota](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [Metrics Server](https://github.com/kubernetes-sigs/metrics-server)
- [Vertical Pod Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)

---

## 🔗 Next Lab

➡️ **[Lab 20 — Horizontal Pod Autoscaler](../lab-20-hpa/README.md)**: Tự động scale ứng dụng dựa trên CPU/Memory usage với HPA.
