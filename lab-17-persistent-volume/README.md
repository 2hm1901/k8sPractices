# Lab 17 — PersistentVolume & PersistentVolumeClaim

## 🎯 Mục tiêu (Objectives)

Sau khi hoàn thành lab này, bạn sẽ có thể:

- Hiểu sự khác biệt giữa ephemeral Volume và PersistentVolume (PV)
- Nắm vững vòng đời (lifecycle) của PV: provisioning → binding → using → reclaiming
- Hiểu và áp dụng đúng các Access Modes: RWO, ROX, RWX, RWOP
- Cấu hình Reclaim Policies: Retain, Delete, Recycle
- Tạo PVC và bind với PV
- Mount PVC vào Pod và Deployment
- Theo dõi Volume status: Available → Bound → Released → Failed

---

## 📋 Prerequisites

- Đã hoàn thành Lab 16 (Secret)
- `kubectl` đã cấu hình kết nối tới cluster
- Đối với hostPath: cần node access (Minikube hoặc kind cluster)
- Hiểu biết cơ bản về Linux filesystem

```bash
kubectl cluster-info
kubectl get nodes
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Volume vs PersistentVolume

```
┌─────────────────────────────────────────────────────────────┐
│                    Ephemeral Volume                         │
│  - Gắn liền với lifecycle của Pod                           │
│  - Khi Pod bị xóa → data mất                               │
│  - Types: emptyDir, configMap, secret, hostPath             │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                   PersistentVolume (PV)                     │
│  - Tồn tại độc lập với Pod lifecycle                        │
│  - Admin provision, developer claim                         │
│  - Types: NFS, iSCSI, cloud volumes, local, ...             │
└─────────────────────────────────────────────────────────────┘
```

### PV/PVC Lifecycle

```
Admin                              Developer
  │                                    │
  │ kubectl apply pv.yaml              │ kubectl apply pvc.yaml
  │                                    │
  ▼                                    ▼
[PV Created]                       [PVC Created]
  │                                    │
  │         Kubernetes binds them      │
  └──────────────────┬─────────────────┘
                     │
                     ▼
              [PV: Bound] ◄──── [PVC: Bound]
                     │
                     │ Pod uses PVC
                     ▼
              [PV: Bound] (in use by Pod)
                     │
                     │ Pod & PVC deleted
                     ▼
         ┌──────────────────────┐
         │    Reclaim Policy    │
         ├──────────────────────┤
         │ Retain → Released    │ (Data kept, manual cleanup)
         │ Delete → Deleted     │ (PV and storage deleted)
         │ Recycle → Available  │ (Deprecated: rm -rf /data/*)
         └──────────────────────┘
```

### Access Modes

| Mode | Viết tắt | Mô tả | Ví dụ use case |
|---|---|---|---|
| ReadWriteOnce | RWO | 1 node đọc+ghi | Database (PostgreSQL, MySQL) |
| ReadOnlyMany | ROX | Nhiều nodes đọc | Static assets, config files |
| ReadWriteMany | RWX | Nhiều nodes đọc+ghi | Shared storage (NFS, CephFS) |
| ReadWriteOncePod | RWOP | 1 pod đọc+ghi (K8s 1.22+) | Strict single-writer |

### Reclaim Policies

```
┌─────────────────────────────────────────────────────────┐
│  Retain  → PV chuyển sang "Released", data được giữ    │
│            Admin phải manually cleanup & make Available │
│                                                         │
│  Delete  → PV và underlying storage bị xóa tự động     │
│            Thường dùng với Dynamic Provisioning         │
│                                                         │
│  Recycle → Deprecated! (dùng Dynamic Provisioning)     │
│            Chạy `rm -rf /data/*` rồi làm Available     │
└─────────────────────────────────────────────────────────┘
```

---

## 🛠️ Thực hành (Hands-on)

### Bước 1: Tạo Namespace

```bash
kubectl create namespace lab17
kubectl config set-context --current --namespace=lab17
```

### Bước 2: Tạo thư mục hostPath trên node

```bash
# Với Minikube: SSH vào node
minikube ssh
sudo mkdir -p /mnt/data/app-data
sudo chmod 777 /mnt/data/app-data
exit

# Với kind: exec vào control-plane container
docker exec -it kind-control-plane bash
mkdir -p /mnt/data/app-data
chmod 777 /mnt/data/app-data
exit

# Verify
minikube ssh "ls -la /mnt/data/"
```

### Bước 3: Tạo PersistentVolume (Admin role)

```bash
# Apply PV manifest
kubectl apply -f manifests/pv-hostpath.yaml

# Kiểm tra PV status
kubectl get pv
```

Expected output:
```
NAME          CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   AGE
pv-app-data   5Gi        RWO            Retain           Available           manual         10s
```

```bash
# Describe PV để xem chi tiết
kubectl describe pv pv-app-data
```

```
Name:            pv-app-data
Capacity:        5Gi
Access Modes:    RWO
Reclaim Policy:  Retain
Status:          Available        ← Sẵn sàng được claim
...
```

### Bước 4: Tạo PersistentVolumeClaim (Developer role)

```bash
kubectl apply -f manifests/pvc-app-data.yaml

# Theo dõi binding process
kubectl get pvc -n lab17 -w
```

Expected output:
```
NAME           STATUS    VOLUME        CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pvc-app-data   Bound     pv-app-data   5Gi        RWO            manual         5s
```

```bash
# PV cũng chuyển sang Bound
kubectl get pv
# STATUS: Bound  CLAIM: lab17/pvc-app-data

# Describe PVC
kubectl describe pvc pvc-app-data -n lab17
```

### Bước 5: Mount PVC vào Pod

```bash
kubectl apply -f manifests/pod-with-pvc.yaml

kubectl wait --for=condition=Ready pod/pod-pvc-demo -n lab17 --timeout=60s

# Ghi data vào volume
kubectl exec pod-pvc-demo -n lab17 -- \
  sh -c 'echo "Hello from Kubernetes PV!" > /data/test.txt'

kubectl exec pod-pvc-demo -n lab17 -- cat /data/test.txt
# Hello from Kubernetes PV!

# Kiểm tra disk usage
kubectl exec pod-pvc-demo -n lab17 -- df -h /data
```

### Bước 6: Test Data Persistence

```bash
# Ghi thêm data
kubectl exec pod-pvc-demo -n lab17 -- \
  sh -c 'date >> /data/timestamps.txt && echo "Pod: pod-pvc-demo" >> /data/timestamps.txt'

# Xóa Pod
kubectl delete pod pod-pvc-demo -n lab17

# Tạo lại Pod mới với cùng PVC
kubectl apply -f manifests/pod-with-pvc.yaml

kubectl wait --for=condition=Ready pod/pod-pvc-demo -n lab17 --timeout=60s

# Data vẫn còn!
kubectl exec pod-pvc-demo -n lab17 -- cat /data/test.txt
# Hello from Kubernetes PV!
kubectl exec pod-pvc-demo -n lab17 -- cat /data/timestamps.txt
```

✅ **Data survived Pod deletion!** Đây là điểm khác biệt cốt lõi của PersistentVolume.

### Bước 7: Deploy Stateful Application với PVC

```bash
kubectl apply -f manifests/deployment-with-pvc.yaml

kubectl get deployment app-with-storage -n lab17
kubectl get pods -n lab17 -l app=app-with-storage

# Xem events nếu có lỗi
kubectl describe pod -n lab17 -l app=app-with-storage
```

**⚠️ Lưu ý về RWO với Deployment:**
```bash
# RWO (ReadWriteOnce) chỉ cho phép 1 node mount
# Nếu Deployment có replicas=2 và Pods trên 2 nodes khác nhau → lỗi!
# Solution: dùng RWX storage (NFS, CephFS) hoặc replicas=1

kubectl scale deployment app-with-storage --replicas=2 -n lab17
kubectl get pods -n lab17 -l app=app-with-storage
# Nếu scheduler đặt cả 2 Pods trên 1 node → OK
# Nếu đặt trên 2 nodes khác → Pod thứ 2 sẽ Pending hoặc Error
```

### Bước 8: Quan sát PV Status Lifecycle

```bash
# Status 1: Available (PV vừa tạo, chưa có PVC bind)
kubectl get pv  # STATUS: Available

# Status 2: Bound (PVC đã bind)
kubectl get pv  # STATUS: Bound

# Xóa PVC để xem Released status
kubectl delete pvc pvc-app-data -n lab17
kubectl get pv  # STATUS: Released (với Retain policy)

# Với Retain policy, PV không Available trở lại tự động
# Admin phải manually clear claimRef để reuse
kubectl patch pv pv-app-data \
  --type json \
  -p '[{"op": "remove", "path": "/spec/claimRef"}]'

kubectl get pv  # STATUS: Available (lại)
```

### Bước 9: Tạo lại PVC và Test Binding Selector

```bash
# Tạo 2 PVs
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-small
  labels:
    type: ssd
    tier: fast
spec:
  capacity:
    storage: 1Gi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Delete
  storageClassName: manual
  hostPath:
    path: /mnt/data/small
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-large
  labels:
    type: hdd
    tier: slow
spec:
  capacity:
    storage: 10Gi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Delete
  storageClassName: manual
  hostPath:
    path: /mnt/data/large
EOF

# PVC với selector - chỉ bind PV có label cụ thể
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-fast-storage
  namespace: lab17
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: manual
  resources:
    requests:
      storage: 1Gi
  selector:
    matchLabels:
      tier: fast  # Chỉ bind với pv-small
EOF

kubectl get pvc -n lab17
kubectl get pv
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# 1. Kiểm tra tất cả PVs
kubectl get pv -o wide

# 2. Kiểm tra tất cả PVCs
kubectl get pvc -n lab17

# 3. Verify data persistence
kubectl exec pod-pvc-demo -n lab17 -- ls -la /data/

# 4. Kiểm tra PV-PVC binding
kubectl get pv pv-app-data -o jsonpath='{.spec.claimRef}' | python3 -m json.tool

# 5. Storage capacity
kubectl exec pod-pvc-demo -n lab17 -- df -h /data

# 6. Kiểm tra access mode
kubectl get pv pv-app-data -o jsonpath='{.spec.accessModes}'
# ["ReadWriteOnce"]
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xóa theo thứ tự: Pod → PVC → PV
kubectl delete -f manifests/deployment-with-pvc.yaml
kubectl delete -f manifests/pod-with-pvc.yaml
kubectl delete -f manifests/pvc-app-data.yaml
kubectl delete -f manifests/pv-hostpath.yaml

# Hoặc xóa namespace (xóa Pod, PVC nhưng PV là cluster-scoped)
kubectl delete namespace lab17

# PV phải xóa riêng (cluster-scoped resource)
kubectl delete pv pv-app-data pv-small pv-large

# Dọn dẹp hostPath data trên node
minikube ssh "sudo rm -rf /mnt/data/*"

# Reset namespace context
kubectl config set-context --current --namespace=default
```

---

## 💡 Tips & Gotchas

### ❌ Lỗi thường gặp

1. **PVC stuck ở Pending**
   ```bash
   kubectl describe pvc <name> -n <ns>
   # Events: no persistent volumes available for this claim...
   ```
   → Không có PV phù hợp (size, accessMode, storageClass không match)

2. **Deployment replicas > 1 với RWO volume**
   - Pods trên cùng 1 node: OK (node có thể mount)
   - Pods trên các nodes khác nhau: Pod thứ 2 bị stuck ở ContainerCreating
   - Fix: Dùng StatefulSet (mỗi pod có PVC riêng) hoặc RWX storage

3. **PV Released nhưng không Available**
   ```bash
   # Với Retain policy, phải manually clear claimRef
   kubectl patch pv <pv-name> --type json \
     -p '[{"op": "remove", "path": "/spec/claimRef"}]'
   ```

4. **hostPath không tồn tại trên node**
   → Pod bị `Error` hoặc file không được tạo
   → SSH vào node để tạo directory trước

### ✅ Best Practices

- **Không dùng hostPath trong production** → dùng NFS, cloud volumes, Ceph
- **Luôn specify storageClassName** để tránh bind nhầm PV
- **Dùng Dynamic Provisioning** (Lab 18) thay vì static PV/PVC thủ công
- **StatefulSet** cho applications cần stable storage identity (database)
- Khai báo PVC trong Pod spec (không hardcode PV name vào Pod)
- Tách biệt storageClassName cho các môi trường: `dev`, `staging`, `prod`

### StorageClass relationship

```
PV ──── storageClassName: "manual"
                │
PVC ─── storageClassName: "manual"  ──→ Match! Kubernetes binds them
```

---

## 📚 Tham khảo (References)

- [Official Docs: Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Configure a Pod to Use a PersistentVolume](https://kubernetes.io/docs/tasks/configure-pod-container/configure-persistent-volume-storage/)
- [Access Modes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes)
- [Reclaim Policy](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#reclaiming)

---

## 🔗 Next Lab

➡️ **[Lab 18 — StorageClass & Dynamic Provisioning](../lab-18-storageclass/README.md)**: Tự động tạo PV với StorageClass và Dynamic Provisioning.
