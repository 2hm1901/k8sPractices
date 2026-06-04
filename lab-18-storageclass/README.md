# Lab 18 — StorageClass & Dynamic Provisioning

## 🎯 Mục tiêu (Objectives)

Sau khi hoàn thành lab này, bạn sẽ có thể:

- Hiểu StorageClass và vai trò của provisioner
- Cấu hình volumeBindingMode: Immediate vs WaitForFirstConsumer
- Tạo PVC với Dynamic Provisioning (không cần tạo PV thủ công)
- Đặt Default StorageClass cho cluster
- Mở rộng (expand) Volume đang sử dụng
- Hiểu khái niệm Volume Snapshot

---

## 📋 Prerequisites

- Đã hoàn thành Lab 17 (PersistentVolume & PVC)
- Cluster có StorageClass provisioner (Minikube có sẵn `standard`, kind cần setup)
- `kubectl` đã cấu hình kết nối tới cluster

```bash
# Kiểm tra StorageClass hiện có
kubectl get storageclass
kubectl get sc  # short form

# Kiểm tra provisioner
kubectl describe sc standard
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Static vs Dynamic Provisioning

```
STATIC PROVISIONING (Lab 17):
Admin                    Developer
  │                          │
  │ Create PV manually       │ Create PVC
  │ (pv-hostpath.yaml)       │ (pvc-app-data.yaml)
  │                          │
  └────── Kubernetes binds ──┘
  (Admin phải biết trước storage needs)

DYNAMIC PROVISIONING (Lab 18):
Admin                    Developer
  │                          │
  │ Create StorageClass      │ Create PVC
  │ (once)                   │   storageClassName: fast
  │                          │
  └── Kubernetes auto-creates PV via provisioner ──┘
  (On-demand, self-service)
```

### StorageClass Components

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast
provisioner: docker.io/hostpath      # Who creates the PV?
parameters:                           # Provisioner-specific options
  type: pd-ssd
reclaimPolicy: Delete                 # What happens when PVC deleted?
allowVolumeExpansion: true            # Can PVC grow?
volumeBindingMode: WaitForFirstConsumer  # When to create PV?
mountOptions:                         # Options passed to mount
  - hard
  - nfsvers=4.1
```

### volumeBindingMode

```
Immediate:
  PVC created → PV created immediately (even if no Pod uses it)
  ⚠️ PV created in a random zone, Pod may be scheduled elsewhere

WaitForFirstConsumer:
  PVC created → Wait...
  Pod scheduled on Node X → PV created in same zone as Node X ✓
  Recommended for cloud environments with zone-aware storage
```

### Cloud Provisioners

| Cloud | Provisioner | Storage Type |
|---|---|---|
| AWS | ebs.csi.aws.com | EBS volumes |
| GCP | pd.csi.storage.gke.io | Persistent Disk |
| Azure | disk.csi.azure.com | Azure Disk |
| Minikube | docker.io/hostpath | hostPath |
| kind | rancher.io/local-path | hostPath |
| On-prem | rook-ceph.rbd.csi.ceph.com | Ceph RBD |

---

## 🛠️ Thực hành (Hands-on)

### Bước 1: Tạo Namespace và kiểm tra provisioner

```bash
kubectl create namespace lab18
kubectl config set-context --current --namespace=lab18

# Xem StorageClasses hiện có
kubectl get sc
kubectl describe sc

# Xem default StorageClass (đánh dấu với *)
kubectl get sc | grep default
```

### Bước 2: Tạo StorageClass tùy chỉnh

```bash
# Apply các StorageClass
kubectl apply -f manifests/storageclass-fast.yaml
kubectl apply -f manifests/storageclass-slow.yaml

kubectl get sc
```

Expected:
```
NAME                 PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
fast                 docker.io/hostpath         Delete          Immediate              true
slow                 docker.io/hostpath         Retain          WaitForFirstConsumer   false
standard (default)   docker.io/hostpath         Delete          Immediate              false
```

```bash
# Mô tả StorageClass
kubectl describe sc fast
kubectl describe sc slow
```

### Bước 3: Dynamic PVC - Tạo PV tự động

```bash
# Apply PVC - KHÔNG cần tạo PV trước
kubectl apply -f manifests/pvc-dynamic.yaml

# Theo dõi - PV được tạo tự động
kubectl get pvc -n lab18 -w
```

```
NAME          STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pvc-dynamic   Pending                                      fast           2s
pvc-dynamic   Bound     pvc-...  10Gi       RWO            fast           5s
```

```bash
# PV được tạo tự động!
kubectl get pv

# Tên PV được auto-generate
# NAME: pvc-a1b2c3d4-...
# STATUS: Bound
# CLAIM: lab18/pvc-dynamic
# STORAGECLASS: fast
```

### Bước 4: Sử dụng PVC trong Pod

```bash
kubectl apply -f manifests/pod-dynamic-storage.yaml

kubectl wait --for=condition=Ready pod/pod-dynamic -n lab18 --timeout=60s

# Ghi data
kubectl exec pod-dynamic -n lab18 -- \
  sh -c 'echo "Dynamic provisioning works!" > /data/test.txt && date >> /data/test.txt'

kubectl exec pod-dynamic -n lab18 -- cat /data/test.txt
```

### Bước 5: Default StorageClass

```bash
# Xem StorageClass nào là default
kubectl get sc

# Đặt StorageClass là default (dùng annotation)
kubectl patch sc fast \
  -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "true"}}}'

# Remove default từ 'standard' (nếu có)
kubectl patch sc standard \
  -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "false"}}}'

kubectl get sc
# fast (default)
```

```bash
# Tạo PVC KHÔNG specify storageClassName → dùng default
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-no-sc
  namespace: lab18
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
  # storageClassName không được chỉ định → dùng default
EOF

kubectl get pvc pvc-no-sc -n lab18
# STORAGECLASS: fast  (default được dùng tự động)
```

### Bước 6: Volume Expansion

```bash
# Điều kiện: StorageClass phải có allowVolumeExpansion: true
# và provisioner phải support resize

# Kiểm tra
kubectl get sc fast -o jsonpath='{.allowVolumeExpansion}'
# true

# PVC hiện tại: 10Gi
kubectl get pvc pvc-dynamic -n lab18

# Mở rộng lên 20Gi (patch PVC)
kubectl patch pvc pvc-dynamic -n lab18 \
  --type merge \
  -p '{"spec": {"resources": {"requests": {"storage": "20Gi"}}}}'

# Theo dõi resize progress
kubectl get pvc pvc-dynamic -n lab18 -w
# STATUS thay đổi từ Bound → ... → Bound
# CAPACITY: 10Gi → 20Gi

# Xem events
kubectl describe pvc pvc-dynamic -n lab18 | tail -20
```

**⚠️ Lưu ý:**
- Chỉ có thể **tăng** capacity, KHÔNG thể giảm
- Một số provisioners yêu cầu Pod phải đang chạy để resize filesystem
- Filesystem resize xảy ra khi Pod mount lại volume

### Bước 7: WaitForFirstConsumer Demo

```bash
# Tạo PVC với StorageClass 'slow' (WaitForFirstConsumer)
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-wait
  namespace: lab18
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: slow
  resources:
    requests:
      storage: 5Gi
EOF

# PVC sẽ ở Pending - chờ Pod được schedule
kubectl get pvc pvc-wait -n lab18
# STATUS: Pending

# PV chưa được tạo!
kubectl get pv | grep pvc-wait || echo "No PV yet"

# Tạo Pod sử dụng PVC này
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: pod-wait-consumer
  namespace: lab18
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: pvc-wait
EOF

# Sau khi Pod được schedule, PV được tạo và PVC bound
kubectl get pvc pvc-wait -n lab18 -w
# Pending → Bound

kubectl get pv | grep pvc-wait
# PV được tạo tự động!
```

### Bước 8: Volume Snapshot (Concept & Setup)

```bash
# Volume Snapshot cần VolumeSnapshot CRDs và snapshot controller
# Kiểm tra xem đã có chưa
kubectl get crd | grep volumesnapshot

# Nếu chưa có, install snapshot CRDs
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml
```

```yaml
# VolumeSnapshotClass
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: csi-aws-vsc
driver: ebs.csi.aws.com
deletionPolicy: Delete

---
# Tạo Snapshot
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: my-snap
spec:
  volumeSnapshotClassName: csi-aws-vsc
  source:
    persistentVolumeClaimName: pvc-dynamic

---
# Restore từ Snapshot
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-from-snapshot
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: fast
  resources:
    requests:
      storage: 10Gi
  dataSource:
    name: my-snap
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# 1. Kiểm tra StorageClasses
kubectl get sc

# 2. Verify dynamic PV creation
kubectl get pv
# PV được tạo tự động với tên pvc-<uuid>

# 3. Verify PVC bound
kubectl get pvc -n lab18
# STATUS: Bound

# 4. Verify data trong Pod
kubectl exec pod-dynamic -n lab18 -- cat /data/test.txt

# 5. Verify volume expansion
kubectl get pvc pvc-dynamic -n lab18 -o jsonpath='{.status.capacity.storage}'
# 20Gi (sau khi resize)

# 6. Kiểm tra events
kubectl get events -n lab18 --sort-by=.lastTimestamp | tail -20
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xóa Pods trước (để release volumes)
kubectl delete pod pod-dynamic pod-wait-consumer -n lab18 --ignore-not-found

# Xóa PVCs (sẽ trigger Delete reclaim policy)
kubectl delete pvc --all -n lab18

# PVs với Delete policy sẽ tự xóa
# PVs với Retain policy phải xóa manually
kubectl get pv  # Kiểm tra còn PV nào không
kubectl delete pv <pv-name>  # Nếu cần

# Xóa custom StorageClasses
kubectl delete sc fast slow

# Xóa namespace
kubectl delete namespace lab18

# Reset default StorageClass về standard (nếu đã thay đổi)
kubectl patch sc standard \
  -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "true"}}}'

kubectl config set-context --current --namespace=default
```

---

## 💡 Tips & Gotchas

### ❌ Lỗi thường gặp

1. **PVC Pending mãi không Bound**
   ```bash
   kubectl describe pvc <name> -n <ns>
   # Events: waiting for a volume to be created
   # → provisioner chưa chạy hoặc không support
   # → StorageClass name sai
   ```

2. **Volume resize bị Pending**
   ```
   Waiting for user to (re-)start a pod to finish file system resize
   ```
   → Cần restart Pod để filesystem được resize

3. **Nhiều default StorageClass**
   ```
   Warning: detected multiple default StorageClasses
   ```
   → Đảm bảo chỉ 1 StorageClass có annotation `is-default-class: "true"`

4. **WaitForFirstConsumer với StatefulSet**
   → StatefulSet tạo PVCs tự động, cần StorageClass support topology

### ✅ Best Practices

- **Dùng WaitForFirstConsumer** trong môi trường multi-zone cloud
- **Tách StorageClass theo tier**: `fast-ssd`, `standard-hdd`, `archive`
- **Enable allowVolumeExpansion** cho production StorageClass
- **Dùng ReclaimPolicy: Retain** cho critical data (không bị xóa nhầm)
- **Monitor PVC usage** để tránh volume full:
  ```bash
  kubectl exec <pod> -- df -h
  ```
- CSI drivers cung cấp nhiều tính năng hơn in-tree provisioners

---

## 📚 Tham khảo (References)

- [Official Docs: StorageClass](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [Dynamic Volume Provisioning](https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/)
- [Volume Expansion](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#expanding-persistent-volumes-claims)
- [CSI Drivers List](https://kubernetes-csi.github.io/docs/drivers.html)
- [Volume Snapshots](https://kubernetes.io/docs/concepts/storage/volume-snapshots/)

---

## 🔗 Next Lab

➡️ **[Lab 19 — Resource Requests & Limits](../lab-19-resource-management/README.md)**: Quản lý CPU và Memory với Requests, Limits, QoS Classes, LimitRange, và ResourceQuota.
