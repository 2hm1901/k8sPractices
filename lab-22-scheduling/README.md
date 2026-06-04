# Lab 22 — Taints, Tolerations & Node Affinity

## 🎯 Mục tiêu (Objectives)

Sau lab này, bạn sẽ hiểu và làm được:
- Hiểu 3 taint effects: **NoSchedule**, **PreferNoSchedule**, **NoExecute**
- Thêm/xóa taints trên nodes
- Tạo Pods với **Tolerations** để bypass taints
- Dùng **NodeSelector** (đơn giản) và **NodeAffinity** (phức tạp)
- Hiểu sự khác biệt giữa `requiredDuringScheduling` và `preferredDuringScheduling`
- Dùng **Pod Affinity** để co-locate Pods
- Dùng **Pod Anti-Affinity** để spread Pods across nodes/zones
- Hiểu **Topology Keys** trong scheduling

---

## 📋 Prerequisites

- Hoàn thành Lab 21
- Cluster có ít nhất **2 worker nodes** (để thấy rõ scheduling decisions)
- Hiểu cơ bản về Kubernetes Scheduler

```bash
# Kiểm tra nodes
kubectl get nodes --show-labels

# Xem labels trên nodes
kubectl describe nodes | grep -A 10 "Labels:"
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Kubernetes Scheduling Flow

```
┌─────────────────────────────────────────────────────────────────┐
│              Kubernetes Scheduler Decision Tree                   │
│                                                                  │
│  Pod created → Filtering → Scoring → Binding                    │
│                    │                                             │
│         ┌──────────▼──────────┐                                  │
│         │   Filtering Phase   │ ← Loại bỏ nodes không phù hợp  │
│         │  • Taints/Tol.      │                                  │
│         │  • NodeAffinity     │                                  │
│         │  • Resource fit     │                                  │
│         │  • PodAffinity      │                                  │
│         └──────────┬──────────┘                                  │
│                    │                                             │
│         ┌──────────▼──────────┐                                  │
│         │   Scoring Phase     │ ← Chọn node tốt nhất            │
│         │  • Preferred rules  │                                  │
│         │  • Spread topology  │                                  │
│         └──────────┬──────────┘                                  │
│                    │                                             │
│         ┌──────────▼──────────┐                                  │
│         │   Binding Phase     │ ← Gán Pod vào node              │
│         └─────────────────────┘                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Taints & Tolerations

```
Taint (trên Node):    key=value:Effect
Toleration (trên Pod): phải match Taint để được schedule lên node đó

Effect:
  NoSchedule        → Pod KHÔNG được schedule lên node (pods hiện tại không bị ảnh hưởng)
  PreferNoSchedule  → Scheduler CỐ TRÁNH, nhưng không bắt buộc
  NoExecute         → Pod KHÔNG được schedule + evict pods hiện tại không có toleration
```

### NodeAffinity Types

```yaml
# REQUIRED: Pod PHẢI được schedule vào node thỏa điều kiện
requiredDuringSchedulingIgnoredDuringExecution:
  # Nếu không có node phù hợp → Pod Pending

# PREFERRED: Scheduler ưu tiên nhưng không bắt buộc  
preferredDuringSchedulingIgnoredDuringExecution:
  # Nếu không có node phù hợp → schedule vào node khác
```

### Pod Affinity vs Anti-Affinity

```
Pod Affinity:      "Tôi muốn chạy CÙNG NODE/ZONE với Pods có label X"
                   → Ứng dụng cache cần gần ứng dụng backend

Pod Anti-Affinity: "Tôi muốn chạy KHÁC NODE/ZONE với Pods có label X"
                   → Spread replicas để HA
```

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Khám phá Node Labels

```bash
# Xem tất cả labels trên nodes
kubectl get nodes --show-labels

# Các labels quan trọng thường có sẵn:
# kubernetes.io/hostname=node1
# topology.kubernetes.io/zone=us-east-1a
# topology.kubernetes.io/region=us-east-1
# node.kubernetes.io/instance-type=t3.medium
# kubernetes.io/os=linux
# kubernetes.io/arch=amd64

# Gán custom labels lên nodes
kubectl label node <node-name> disktype=ssd
kubectl label node <node-name> environment=production

# Xem node labels sau khi gán
kubectl get nodes --show-labels | grep disktype
```

---

### Step 2: Thực hành Taints & Tolerations

#### 2a. Thêm Taint lên Node

```bash
# Lấy tên nodes
NODES=($(kubectl get nodes --no-headers -o custom-columns=NAME:.metadata.name))
NODE1=${NODES[0]}
NODE2=${NODES[1]}

echo "Node 1: $NODE1"
echo "Node 2: $NODE2"

# Thêm taint NoSchedule lên Node2
kubectl taint node $NODE2 dedicated=gpu-workload:NoSchedule

# Kiểm tra taint đã gán
kubectl describe node $NODE2 | grep -A 5 "Taints:"
# Output: dedicated=gpu-workload:NoSchedule
```

#### 2b. Deploy Pod KHÔNG có toleration (sẽ tránh Node2)

```bash
# Deploy Pod thông thường
kubectl run no-toleration --image=nginx --restart=Never

# Xem Pod được schedule vào node nào
kubectl get pod no-toleration -o wide

# Pod sẽ LUÔN vào Node1 (vì Node2 có taint NoSchedule)
```

#### 2c. Deploy Pod CÓ toleration (có thể vào Node2)

```bash
# Tạo Pod với toleration
kubectl apply -f manifests/pod-with-toleration.yaml

# Xem Pod được schedule vào node nào
kubectl get pod pod-with-toleration -o wide

# Pod có thể vào cả Node1 và Node2
```

#### 2d. Test NoExecute Taint

```bash
# Deploy một pod bình thường
kubectl run test-no-execute --image=nginx --restart=Never

# Xem Pod đang ở node nào
kubectl get pod test-no-execute -o wide

# Thêm taint NoExecute vào node đó
NODE=$(kubectl get pod test-no-execute -o jsonpath='{.spec.nodeName}')
kubectl taint node $NODE maintenance=true:NoExecute

# Theo dõi Pod bị evict ngay lập tức!
kubectl get pod test-no-execute -w

# Xóa taint sau khi test
kubectl taint node $NODE maintenance=true:NoExecute-
```

#### 2e. Xóa Taint

```bash
# Xóa taint bằng cách thêm dấu '-' ở cuối
kubectl taint node $NODE2 dedicated=gpu-workload:NoSchedule-

# Kiểm tra đã xóa
kubectl describe node $NODE2 | grep "Taints:"
# Taints: <none>
```

---

### Step 3: NodeSelector (Cách đơn giản nhất)

```bash
# Label node với disktype=ssd
kubectl label node $NODE1 disktype=ssd

# Deploy pod với nodeSelector
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: pod-with-nodeselector
spec:
  containers:
  - name: nginx
    image: nginx
  nodeSelector:
    disktype: ssd   # Chỉ schedule lên node có label này
EOF

# Xem Pod được schedule vào node nào
kubectl get pod pod-with-nodeselector -o wide
# Sẽ luôn vào Node1 (có disktype=ssd)
```

> ⚠️ **NodeSelector là dạng "required"** — nếu không có node có label đó, Pod sẽ Pending mãi. Dùng NodeAffinity nếu cần flexible hơn.

---

### Step 4: NodeAffinity — Required và Preferred

```bash
# Tạo Pod với NodeAffinity required + preferred
kubectl apply -f manifests/pod-node-affinity.yaml

# Xem Pod được schedule đâu
kubectl get pod pod-node-affinity -o wide

# Xem scheduling events
kubectl describe pod pod-node-affinity | grep -A 10 "Events:"
```

**Thử test "preferred" không có node match:**
```bash
# Remove label disktype=ssd khỏi tất cả nodes
kubectl label node --all disktype-

# Apply pod với preferred affinity → vẫn schedule được (vào node bất kỳ)
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: pod-preferred-test
spec:
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 1
        preference:
          matchExpressions:
          - key: disktype
            operator: In
            values: [ssd]
  containers:
  - name: nginx
    image: nginx
EOF

kubectl get pod pod-preferred-test -o wide
# Pod vẫn scheduled thành công (không bị Pending)

# Cleanup
kubectl delete pod pod-preferred-test
```

---

### Step 5: Pod Anti-Affinity — Spread Replicas Across Nodes

```bash
# Deploy với Anti-Affinity để mỗi node chỉ có 1 replica
kubectl apply -f manifests/pod-anti-affinity.yaml

# Xem các Pods được spread ra các nodes
kubectl get pods -l app=ha-app -o wide

# Expected: Mỗi node chạy đúng 1 Pod
# NAME          READY   STATUS    NODE
# ha-app-xxx1   1/1     Running   node1
# ha-app-xxx2   1/1     Running   node2
# ha-app-xxx3   1/1     Running   node3
```

**Giải thích anti-affinity trong manifest:**
```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:  # Bắt buộc spread
    - labelSelector:
        matchExpressions:
        - key: app
          operator: In
          values: [ha-app]
      topologyKey: kubernetes.io/hostname  # Mỗi hostname chỉ 1 Pod
```

---

### Step 6: Spread across Zones với Topology Keys

```bash
# Label nodes với zones (simulate multi-zone cluster)
kubectl label node $NODE1 topology.kubernetes.io/zone=us-east-1a
kubectl label node $NODE2 topology.kubernetes.io/zone=us-east-1b

# Deploy với zone spread
kubectl apply -f manifests/deployment-zone-spread.yaml

# Xem pods được spread across zones
kubectl get pods -l app=zone-spread -o custom-columns="NAME:.metadata.name,NODE:.spec.nodeName,STATUS:.status.phase"

# Annotate nodes để xem zone
kubectl get pods -l app=zone-spread -o wide
```

**TopologySpreadConstraints (cách hiện đại hơn Anti-Affinity):**
```yaml
# Trong deployment-zone-spread.yaml sử dụng TopologySpreadConstraints
topologySpreadConstraints:
- maxSkew: 1                              # Chênh lệch tối đa 1 Pod giữa zones
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule        # Strict: không schedule nếu vi phạm
  labelSelector:
    matchLabels:
      app: zone-spread
```

---

### Step 7: Pod Affinity — Co-locate Pods

```bash
# Deploy backend service trước
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cache-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cache
  template:
    metadata:
      labels:
        app: cache
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
EOF

# Deploy frontend với Pod Affinity (cùng node với cache)
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      affinity:
        podAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values: [cache]
              topologyKey: kubernetes.io/hostname
      containers:
      - name: nginx
        image: nginx
EOF

# Xem frontend có chạy cùng node với cache không
kubectl get pods -o wide | grep -E "cache|frontend"
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# 1. Kiểm tra taints trên nodes
kubectl describe nodes | grep -A 3 "Taints:"

# 2. Kiểm tra pod scheduling
kubectl get pods -o wide

# 3. Kiểm tra anti-affinity đang hoạt động
kubectl get pods -l app=ha-app -o wide
# → Mỗi node chỉ có 1 pod

# 4. Xem scheduler events
kubectl get events --sort-by='.lastTimestamp' | grep -i "schedule\|failedScheduling"

# 5. Xem affinity config của pod đang chạy
kubectl get pod pod-node-affinity -o jsonpath='{.spec.affinity}' | python3 -m json.tool
```

**Checklist:**
- [ ] Taint/Toleration: Pod không có toleration tránh được node có taint
- [ ] Pod có toleration có thể schedule vào node có taint
- [ ] NodeAffinity required: Pod không schedule vào node không match
- [ ] NodeAffinity preferred: Pod vẫn schedule dù không có node match
- [ ] Anti-Affinity: Pods được spread ra nhiều nodes

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xóa custom labels trên nodes
kubectl label node --all disktype- environment- --ignore-not-found
kubectl label node $NODE1 topology.kubernetes.io/zone- --ignore-not-found
kubectl label node $NODE2 topology.kubernetes.io/zone- --ignore-not-found

# Xóa taints còn lại
kubectl taint node --all dedicated- maintenance- --ignore-not-found 2>/dev/null || true

# Xóa pods và deployments
kubectl delete -f manifests/ --ignore-not-found
kubectl delete pod no-toleration test-no-execute pod-with-nodeselector --ignore-not-found
kubectl delete deployment cache-service frontend --ignore-not-found

# Kiểm tra đã sạch
kubectl get pods
kubectl describe nodes | grep "Taints:"
```

---

## 💡 Tips & Gotchas

### ⚠️ Thường gặp

1. **Pod bị Pending vì NodeAffinity quá strict**
   ```bash
   kubectl describe pod <pod-name> | grep -A 5 "Events:"
   # "0/3 nodes are available: 3 node(s) didn't match Pod's node affinity"
   # → Kiểm tra labels trên nodes: kubectl get nodes --show-labels
   ```

2. **Anti-Affinity khiến replica không scale được**
   ```bash
   # Nếu dùng required anti-affinity và số replicas > số nodes → Pod Pending
   # Giải pháp: Dùng preferred thay required, hoặc tăng số nodes
   ```

3. **Taint NoExecute evict pods production**
   ```bash
   # CẢNH BÁO: kubectl taint node <node> key=val:NoExecute
   # sẽ EVICT ngay lập tức tất cả pods không có toleration
   # → Luôn dùng NoSchedule hoặc PreferNoSchedule trước khi maintenance
   ```

4. **Topology key không hợp lệ**
   ```bash
   # topologyKey phải là label key tồn tại trên nodes
   # Phổ biến: kubernetes.io/hostname, topology.kubernetes.io/zone
   ```

### 💡 Best Practices

- **Control Plane nodes** mặc định có taint `node-role.kubernetes.io/control-plane:NoSchedule` → workloads không bị schedule lên đó
- Dùng **`preferredDuringScheduling`** thay `required` khi có thể — flexible hơn
- **TopologySpreadConstraints** (K8s 1.19+) là cách hiện đại để spread pods — thay thế anti-affinity phức tạp
- **Không hardcode node names** trong affinity — dùng labels
- Kết hợp **Taint + NodeAffinity** cho dedicated node pools (GPU, high-mem)

---

## 📚 Tham khảo (References)

- [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
- [Assigning Pods to Nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)
- [Pod Affinity/Anti-Affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#affinity-and-anti-affinity)
- [TopologySpreadConstraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/)

---

## 🔗 Next Lab

➡️ **[Lab 23 — Pod Disruption Budget (PDB)](../lab-23-pdb/README.md)**

Lab 23 sẽ học cách bảo vệ ứng dụng khỏi **involuntary disruption** khi node maintenance, rolling updates, hoặc cluster scaling với Pod Disruption Budget.
