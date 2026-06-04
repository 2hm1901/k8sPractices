# Lab 07 — DaemonSet & Static Pod

## 🎯 Mục tiêu (Objectives)

Sau lab này bạn sẽ hiểu và làm được:
- Hiểu **DaemonSet use cases**: log agents, monitoring, network plugins
- So sánh **DaemonSet vs Deployment**
- Cấu hình **UpdateStrategy** cho DaemonSet (`RollingUpdate`, `OnDelete`)
- Dùng **nodeSelector** và **tolerations** để kiểm soát DaemonSet chạy trên node nào
- Hiểu **Static Pods** — pods được kubelet quản lý trực tiếp (không qua API server)
- Biết Static Pods được dùng ở đâu trong control plane

---

## 📋 Prerequisites

- Đã hoàn thành Lab 06 (Deployment)
- Cluster với ít nhất 1 worker node (multi-node tốt hơn)
- Quyền truy cập node (cho phần Static Pod)

```bash
kubectl cluster-info
kubectl get nodes -o wide
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### DaemonSet là gì?

**DaemonSet** đảm bảo rằng **mỗi node** (hoặc một số node được chọn) đều chạy **một bản sao của Pod**. Khi node mới được thêm vào cluster, Pod sẽ tự động được tạo trên đó. Khi node bị xoá, Pod cũng bị xoá theo.

```
Cluster với 3 nodes:

Node 1          Node 2          Node 3
┌──────────┐   ┌──────────┐   ┌──────────┐
│ fluentd  │   │ fluentd  │   │ fluentd  │  ← DaemonSet (1 pod/node)
│ ──────── │   │ ──────── │   │ ──────── │
│ app-pod  │   │ app-pod  │   │          │  ← Deployment (3 replicas)
│ app-pod  │   │          │   │          │
└──────────┘   └──────────┘   └──────────┘

Thêm Node 4 vào cluster:
Node 4
┌──────────┐
│ fluentd  │  ← DaemonSet tự động tạo pod mới!
└──────────┘
```

### Use Cases của DaemonSet

| Use Case | Ví dụ |
|----------|-------|
| **Log collection** | Fluentd, Filebeat, Logstash |
| **Monitoring/Metrics** | Prometheus Node Exporter, Datadog Agent |
| **Network plugins** | Calico, Flannel, Weave Net |
| **Storage plugins** | Ceph, GlusterFS |
| **Security agents** | Falco, Sysdig |
| **GPU drivers** | NVIDIA device plugin |

### DaemonSet vs Deployment

| Tính năng | DaemonSet | Deployment |
|-----------|-----------|------------|
| Số pod | 1 per node | Tổng số cố định |
| Scheduling | Trên mỗi node | Bất kỳ node nào |
| Scale | Theo số nodes | Thủ công/HPA |
| Use case | System daemons | Application pods |
| Node affinity | Implicit | Explicit |

### Static Pod là gì?

**Static Pod** được kubelet tạo ra **trực tiếp** từ file YAML trên node, **không thông qua API server**.

```
Normal Pod flow:
User → kubectl → API Server → Scheduler → kubelet → Container

Static Pod flow:
File YAML trên node → kubelet → Container
(không cần API Server, Scheduler)
```

**Đặc điểm của Static Pod:**
- Kubelet đọc file từ `staticPodPath` (thường `/etc/kubernetes/manifests/`)
- Kubernetes tạo "mirror pod" trên API server (chỉ để hiển thị, không thể xoá qua kubectl)
- Nếu Static Pod crash → kubelet tự restart
- **Control plane components** (etcd, kube-apiserver, kube-controller-manager, kube-scheduler) là Static Pods!

```bash
# Xem static pods của control plane (trên minikube hoặc kubeadm cluster)
kubectl get pods -n kube-system
# etcd-minikube
# kube-apiserver-minikube
# kube-controller-manager-minikube
# kube-scheduler-minikube
```

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Setup namespace

```bash
kubectl create namespace lab07
kubectl config set-context --current --namespace=lab07
```

### Step 2: Deploy DaemonSet Fluentd (Log Collector)

```bash
kubectl apply -f manifests/daemonset-fluentd.yaml

# Xem DaemonSet
kubectl get daemonset -n lab07
# NAME             DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR
# fluentd-ds       1         1         1       1            1           <none>

# Xem pods và chúng đang chạy trên node nào
kubectl get pods -n lab07 -o wide
```

> Số pods = Số worker nodes. Nếu chỉ có 1 node (minikube) → 1 pod.

```bash
# Mô tả DaemonSet
kubectl describe daemonset fluentd-ds -n lab07
```

### Step 3: Deploy Node Exporter DaemonSet

```bash
kubectl apply -f manifests/daemonset-node-exporter.yaml

# Xem cả 2 DaemonSets
kubectl get ds -n lab07
```

### Step 4: Kiểm tra DaemonSet tự động thêm pod khi node mới join

**Với minikube** (tạo thêm node):
```bash
# Thêm node thứ 2 vào minikube cluster
minikube node add

# Quan sát — DaemonSet tự động tạo pod trên node mới
kubectl get pods -n lab07 -o wide -w
```

**Với kind** (multi-node cluster):
```bash
# Xem config kind cluster
kind get clusters
```

### Step 5: nodeSelector — Chạy DaemonSet chỉ trên node được chọn

Label một node cụ thể:
```bash
# Xem nodes và labels
kubectl get nodes --show-labels

# Label một node
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl label node $NODE_NAME role=monitoring

# DaemonSet với nodeSelector sẽ chỉ chạy trên node có label này
```

Tạo DaemonSet chỉ chạy trên monitoring nodes:
```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: monitoring-only-ds
  namespace: lab07
spec:
  selector:
    matchLabels:
      app: monitoring-agent
  template:
    metadata:
      labels:
        app: monitoring-agent
    spec:
      nodeSelector:
        role: monitoring    # Chỉ chạy trên node có label role=monitoring
      containers:
      - name: agent
        image: busybox:1.35
        command: ["sh", "-c", "while true; do echo 'Monitoring...'; sleep 30; done"]
        resources:
          limits:
            cpu: "50m"
            memory: "32Mi"
EOF

kubectl get pods -n lab07 -o wide
```

### Step 6: Tolerations — Chạy DaemonSet trên Master/Control Plane nodes

Mặc định, master node có **taint** ngăn pods thường chạy trên đó. DaemonSet cần tolerations:

```bash
# Xem taints trên nodes
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints

# Với kubeadm cluster, master có taint: node-role.kubernetes.io/control-plane:NoSchedule
```

Tạo DaemonSet với toleration để chạy trên ALL nodes (kể cả master):
```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: all-nodes-ds
  namespace: lab07
spec:
  selector:
    matchLabels:
      app: all-nodes-agent
  template:
    metadata:
      labels:
        app: all-nodes-agent
    spec:
      # Tolerate tất cả taints — cho phép chạy trên mọi node
      tolerations:
      - operator: Exists    # Tolerate bất kỳ taint nào
      containers:
      - name: agent
        image: busybox:1.35
        command: ["sh", "-c", "echo 'Running on $(hostname)'; sleep 3600"]
        resources:
          limits:
            cpu: "10m"
            memory: "16Mi"
EOF
```

### Step 7: DaemonSet Rolling Update

```bash
# Kiểm tra update strategy hiện tại
kubectl get ds fluentd-ds -n lab07 -o jsonpath='{.spec.updateStrategy}'

# Update image của DaemonSet
kubectl set image daemonset/fluentd-ds fluentd=fluent/fluentd:v1.16 -n lab07

# Watch quá trình update
kubectl rollout status daemonset/fluentd-ds -n lab07
kubectl get pods -n lab07 -w
```

### Step 8: Khám phá Static Pods (Lý thuyết + Thực hành)

**Trên minikube:**
```bash
# SSH vào minikube node
minikube ssh

# Xem thư mục chứa static pod manifests
ls /etc/kubernetes/manifests/
# etcd.yaml
# kube-apiserver.yaml
# kube-controller-manager.yaml
# kube-scheduler.yaml

# Xem nội dung một static pod
cat /etc/kubernetes/manifests/kube-apiserver.yaml

# Thoát khỏi minikube ssh
exit
```

**Tạo Static Pod thủ công:**
```bash
# SSH vào node
minikube ssh

# Tạo file static pod
sudo cat > /etc/kubernetes/manifests/my-static-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: my-static-pod
  namespace: default
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    ports:
    - containerPort: 80
EOF

# Kubelet sẽ tự động tạo pod này
exit

# Kiểm tra (sẽ thấy mirror pod trên API server)
kubectl get pods -A | grep static
```

**Xoá Static Pod** → Chỉ có thể xoá file trên node:
```bash
minikube ssh
sudo rm /etc/kubernetes/manifests/my-static-pod.yaml
exit
# Pod sẽ tự biến mất
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# 1. Xem tất cả DaemonSets
kubectl get daemonset -n lab07

# 2. Mỗi DaemonSet có bao nhiêu pods?
kubectl get ds -n lab07 -o custom-columns=\
NAME:.metadata.name,\
DESIRED:.status.desiredNumberScheduled,\
CURRENT:.status.currentNumberScheduled,\
READY:.status.numberReady

# 3. Pods đang chạy trên nodes nào?
kubectl get pods -n lab07 -o wide

# 4. Kiểm tra logs của fluentd
kubectl logs -l app=fluentd -n lab07 --tail=20

# 5. Xem events
kubectl get events -n lab07 --sort-by='.lastTimestamp'
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xoá namespace và tất cả resources
kubectl delete namespace lab07

# Xoá label đã thêm vào node
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl label node $NODE_NAME role-

# Nếu đã tạo static pod, xoá file trên node
minikube ssh -- sudo rm -f /etc/kubernetes/manifests/my-static-pod.yaml

# Reset namespace
kubectl config set-context --current --namespace=default
```

---

## 💡 Tips & Gotchas

1. **DaemonSet không chạy trên master** mặc định vì master node có taint. Cần thêm tolerations nếu cần.

2. **`updateStrategy: OnDelete`** — Pod chỉ được update khi bạn **tự xoá** pod thủ công. Hữu ích khi cần kiểm soát hoàn toàn quá trình update.
   ```yaml
   spec:
     updateStrategy:
       type: OnDelete  # Thay vì RollingUpdate
   ```

3. **DaemonSet không cần replicas field**: Số pod được xác định bởi số nodes, không phải `spec.replicas`.

4. **Static Pods có suffix là tên node**: `my-static-pod-minikube` (minikube là tên node).

5. **Không thể xoá Static Pod qua kubectl**: `kubectl delete pod my-static-pod` sẽ không có tác dụng lâu dài — kubelet sẽ recreate ngay lập tức. Phải xoá file YAML trên node.

6. **kubelet config path**: Xem đường dẫn `staticPodPath`:
   ```bash
   # Trên node
   sudo cat /var/lib/kubelet/config.yaml | grep staticPodPath
   ```

---

## 📚 Tham khảo (References)

- [DaemonSet | Kubernetes Docs](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)
- [Static Pods](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/)
- [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)

---

## 🔗 Next Lab

➡️ [Lab 08 — StatefulSet & Headless Service](../lab-08-statefulset/README.md)
