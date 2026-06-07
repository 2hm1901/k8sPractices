# Lab 04 — Multi-container Pod & Init Container

## 🎯 Mục tiêu

Sau lab này bạn sẽ:
- Hiểu và phân biệt 3 design pattern: **Sidecar, Ambassador, Adapter**
- Biết cách dùng **Init Container** để pre-setup trước khi main container khởi động
- Chia sẻ dữ liệu giữa containers trong cùng Pod qua **emptyDir volume**
- Hiểu thứ tự khởi động: Init containers → Main containers

## 📋 Prerequisites

- Hoàn thành Lab 03 (Pod Lifecycle)
- Cluster đang chạy: `kubectl get nodes`

## 🧠 Lý thuyết nhanh

Một Pod có thể chứa nhiều containers. Chúng chia sẻ:
- Cùng **network namespace** (localhost với nhau)
- Cùng **IPC namespace**
- Có thể chia sẻ **volumes**

```
┌─────────────────────────────────────┐
│               Pod                   │
│  ┌────────────┐  ┌────────────────┐ │
│  │   Main     │  │    Sidecar     │ │
│  │ Container  │  │  Container     │ │
│  └─────┬──────┘  └───────┬────────┘ │
│        │    emptyDir      │         │
│        └────────┬─────────┘         │
│           Shared Volume             │
└─────────────────────────────────────┘
```

### Các Pattern chính

| Pattern | Mục đích | Ví dụ |
|---------|----------|-------|
| **Sidecar** | Mở rộng chức năng main container | Log shipper, metrics exporter |
| **Ambassador** | Proxy kết nối ra ngoài | Envoy proxy, connection pooling |
| **Adapter** | Chuẩn hóa output của main | Metrics format converter |

### Init Container

- Chạy **trước** main containers
- Chạy **tuần tự** (init-1 xong → init-2 → ... → main)
- Nếu Init Container **fail**, Pod sẽ restart (theo restartPolicy)
- Dùng để: download config, wait for dependency, setup permissions

## 🛠️ Thực hành

### Step 1: Sidecar Pattern — Log Shipper

Main container ghi log vào file, sidecar đọc và forward.

```bash
kubectl apply -f manifests/pod-sidecar.yaml
kubectl get pod sidecar-pod
```

Kiểm tra log từ sidecar (log-tailer):
```bash
kubectl logs sidecar-pod -c main-app
kubectl logs sidecar-pod -c log-tailer
```

Xem file được chia sẻ:
```bash
kubectl exec sidecar-pod -c main-app -- ls /var/log/app/
kubectl exec sidecar-pod -c log-tailer -- ls /var/log/app/
```

### Step 2: Init Container — Wait for Dependency

Init container chờ service `myservice` sẵn sàng trước khi main khởi động.

```bash
kubectl apply -f manifests/pod-init-container.yaml
```

Quan sát trạng thái:
```bash
kubectl get pod init-demo -w
# Output:
# NAME        READY   STATUS     RESTARTS   AGE
# init-demo   0/1     Init:0/2   0          5s
# init-demo   0/1     Init:1/2   0          10s
# init-demo   1/1     Running    0          15s
```

Xem log của init container:
```bash
kubectl logs init-demo -c init-check-service
kubectl logs init-demo -c init-download-config
kubectl logs init-demo -c main-app
```

### Step 3: Ambassador Pattern

```bash
kubectl apply -f manifests/pod-ambassador.yaml
kubectl get pod ambassador-pod

# Main app kết nối localhost:5432 → ambassador proxy → external DB
kubectl logs ambassador-pod -c main-app
kubectl logs ambassador-pod -c db-proxy
```

### Step 4: Kiểm tra shared emptyDir

```bash
# Vào main container và ghi file
kubectl exec sidecar-pod -c main-app -- sh -c "echo 'hello from main' >> /var/log/app/test.log"

# Từ sidecar container đọc file vừa ghi
kubectl exec sidecar-pod -c log-tailer -- cat /var/log/app/test.log
```

### Step 5: Mô phỏng Init Container fail

```bash
# Tạo pod với init container sẽ fail
kubectl run init-fail-demo --image=busybox \
  --overrides='{"spec":{"initContainers":[{"name":"init-fail","image":"busybox","command":["sh","-c","exit 1"]}],"containers":[{"name":"main","image":"nginx"}]}}'

kubectl get pod init-fail-demo -w
# Sẽ thấy: Init:CrashLoopBackOff
kubectl logs init-fail-demo -c init-fail
kubectl delete pod init-fail-demo
```

## ✅ Kiểm tra kết quả

```bash
# Liệt kê tất cả containers trong pod
kubectl get pod sidecar-pod -o jsonpath='{.spec.containers[*].name}'
# Output: main-app log-tailer

kubectl get pod init-demo -o jsonpath='{.spec.initContainers[*].name}'
# Output: init-check-service init-download-config

# Xem events
kubectl describe pod sidecar-pod | grep -A 20 Events
```

## 🧹 Dọn dẹp

```bash
kubectl delete pod sidecar-pod init-demo ambassador-pod --ignore-not-found
# hoặc
kubectl delete -f manifests/
```

## 💡 Tips & Gotchas

- **Gotcha**: Init containers không có liveness/readiness probe — chúng phải exit 0 để được coi là thành công
- **Tip**: Dùng `kubectl describe pod` để xem trạng thái từng init container
- **Gotcha**: Containers trong Pod chia sẻ network namespace, nhưng KHÔNG chia sẻ filesystem (trừ khi mount chung volume)
- **Tip**: Sidecar container nên có resource limits riêng để không "ăn" tài nguyên của main container
- **Best practice**: Tên container nên mô tả rõ vai trò: `app`, `sidecar-logger`, `proxy`

## 📚 Tham khảo

- [Init Containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)
- [Sidecar Containers (K8s 1.29+)](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/)
- [Multi-Container Pod Design Patterns](https://kubernetes.io/blog/2015/06/the-distributed-system-toolkit-patterns/)

## 🔗 Next Lab

➡️ [Lab 05 — ReplicaSet & Self-healing](../lab-05-replicaset/README.md)
