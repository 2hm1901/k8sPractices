# Lab 35 — Multi-cluster Management

## 🎯 Mục tiêu (Objectives)

Sau khi hoàn thành lab này, bạn sẽ:
- Hiểu lý do và khi nào cần multi-cluster setup
- Quản lý nhiều kubeconfig với `kubectl` và `kubectx/kubens`
- Sử dụng Cluster API (CAPI) để provisioning clusters khai báo
- Triển khai ArgoCD multi-cluster cho cross-cluster deployment
- Khám phá multi-cluster service discovery với Submariner
- Cấu hình multi-cluster Ingress và ExternalDNS
- Thiết kế Disaster Recovery pattern cho production

---

## 📋 Prerequisites

- Lab 34 (ArgoCD) đã hoàn thành
- `kubectl` với quyền cluster-admin
- `kubectx` và `kubens`: `brew install kubectx`
- `clusterctl` (Cluster API CLI): `brew install clusterctl`
- Ít nhất 2 clusters (có thể dùng kind hoặc minikube)
- Cloud provider credentials (nếu dùng CAPI với AWS/GCP/Azure)

```bash
# Cài đặt công cụ
brew install kubectx  # kubectl context manager
brew install clusterctl  # Cluster API CLI

# Tạo 2 local clusters để thực hành
kind create cluster --name cluster-hub   --config kind-hub.yaml
kind create cluster --name cluster-spoke --config kind-spoke.yaml

# Verify
kubectl config get-contexts
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Tại sao Multi-cluster?

```
┌─────────────────────────────────────────────────────────────┐
│              WHY MULTI-CLUSTER?                             │
│                                                             │
│  1. HIGH AVAILABILITY                                       │
│     cluster-us-east ◄──► cluster-us-west                  │
│     Nếu 1 cluster down → traffic chuyển sang cluster khác  │
│                                                             │
│  2. GEO-DISTRIBUTION                                        │
│     cluster-asia  cluster-europe  cluster-us               │
│     Users kết nối tới cluster gần nhất (latency thấp)      │
│                                                             │
│  3. ISOLATION                                               │
│     cluster-prod  ≠  cluster-staging  ≠  cluster-dev      │
│     Blast radius giới hạn, compliance requirements          │
│                                                             │
│  4. SCALE LIMITS                                            │
│     1 cluster: ~5000 nodes, ~300k pods                     │
│     Multi-cluster: unlimited horizontal scaling             │
│                                                             │
│  5. TEAM AUTONOMY                                           │
│     Team A → cluster-a  |  Team B → cluster-b             │
│     Không conflict resources, independent upgrades          │
└─────────────────────────────────────────────────────────────┘
```

### Multi-cluster Topology Patterns

```
Pattern 1: Hub-and-Spoke (ArgoCD)
──────────────────────────────────
        ┌──────────────┐
        │  Hub Cluster  │  ← ArgoCD, management tools
        │  (Control     │
        │   Plane)      │
        └──────┬───────┘
               │
       ┌───────┼───────┐
       │       │       │
   ┌───▼──┐ ┌──▼──┐ ┌──▼──┐
   │Spoke1│ │Spoke│ │Spoke│  ← Workload clusters
   │ dev  │ │stg  │ │prod │
   └──────┘ └─────┘ └─────┘

Pattern 2: Mesh (Federation)
─────────────────────────────
   cluster-A ◄──► cluster-B
       │               │
       └───────┬───────┘
           cluster-C
   (tất cả đều equal peers)

Pattern 3: Active-Active (DR)
──────────────────────────────
   Region US ◄──Load──► Region EU
   (cùng workloads, cross-region sync)
```

### Cluster API (CAPI) Architecture

```
Management Cluster                    Workload Cluster
──────────────────                    ────────────────
CAPI Core Controller    ──────────►   (được tạo và quản lý)
CAPD/CAPG/CAPA Provider
  (Docker/GCP/AWS)

Declarative cluster lifecycle:
  - Tạo cluster = apply YAML
  - Scale = edit MachineDeployment replicas
  - Upgrade = edit KubeadmControlPlane version
```

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Quản lý KubeConfig đa cluster

```bash
# Merge nhiều kubeconfig
KUBECONFIG=~/.kube/config:~/.kube/cluster-b.yaml kubectl config view --merge --flatten > ~/.kube/merged-config
export KUBECONFIG=~/.kube/merged-config

# Đổi tên contexts cho dễ nhớ
kubectl config rename-context kind-cluster-hub   hub
kubectl config rename-context kind-cluster-spoke spoke-prod

# Dùng kubectx để switch nhanh
kubectx            # list tất cả contexts
kubectx hub        # switch sang hub cluster
kubectx spoke-prod # switch sang production spoke
kubectx -          # switch về context trước

# Dùng kubens để switch namespace
kubens             # list namespaces trong context hiện tại
kubens production  # switch namespace

# Alias hữu ích
alias kh='kubectl --context=hub'
alias ks='kubectl --context=spoke-prod'
```

### Step 2: Cluster API — Provisioning Declarative

```bash
# Bước 1: Khởi tạo Management Cluster với Docker provider (local)
export CLUSTER_TOPOLOGY=true
clusterctl init --infrastructure docker

# Bước 2: Xem providers đã cài
clusterctl describe provider --all

# Bước 3: Generate cluster manifest
clusterctl generate cluster workload-cluster-1 \
  --infrastructure docker \
  --kubernetes-version v1.28.0 \
  --control-plane-machine-count 1 \
  --worker-machine-count 2 \
  > manifests/cluster-api-cluster.yaml

# Bước 4: Apply để tạo cluster
kubectl apply -f manifests/cluster-api-cluster.yaml

# Bước 5: Theo dõi cluster được tạo
kubectl get clusters -A
kubectl get machines -A
kubectl get machinedeployments -A

# Bước 6: Lấy kubeconfig của cluster mới
clusterctl get kubeconfig workload-cluster-1 > ~/.kube/workload-cluster-1.kubeconfig
export KUBECONFIG=~/.kube/workload-cluster-1.kubeconfig
kubectl get nodes
```

```bash
# Scale cluster (declarative)
kubectl patch machinedeployment workload-cluster-1-md-0 \
  -n default \
  --type=merge \
  --patch='{"spec":{"replicas": 5}}'

# Upgrade Kubernetes version (rolling)
kubectl patch kubeadmcontrolplane workload-cluster-1-control-plane \
  -n default \
  --type=merge \
  --patch='{"spec":{"version": "v1.29.0"}}'
```

### Step 3: ArgoCD Multi-cluster

```bash
# Đảm bảo ArgoCD đang chạy trên hub cluster
kubectx hub
kubectl get pods -n argocd

# Thêm spoke cluster vào ArgoCD
argocd cluster add spoke-prod \
  --name spoke-production \
  --in-cluster  # nếu ArgoCD cùng cluster với spoke

# Thêm cluster bên ngoài
argocd cluster add spoke-prod \
  --name spoke-prod \
  --kubeconfig ~/.kube/spoke-prod.kubeconfig

# List clusters trong ArgoCD
argocd cluster list

# Deploy app lên spoke cluster
argocd app create my-app-prod \
  --repo https://github.com/myorg/k8s-manifests \
  --path apps/my-app/overlays/prod \
  --dest-server $(argocd cluster list | grep spoke-prod | awk '{print $1}') \
  --dest-namespace production \
  --project my-project

# ApplicationSet với cluster generator
kubectl apply -f manifests/argocd-applicationset.yaml
```

### Step 4: Multi-cluster Service Discovery với Submariner

Submariner cho phép Pods ở cluster A kết nối tới Services ở cluster B:

```bash
# Cài đặt subctl (Submariner CLI)
curl -Ls https://get.submariner.io | bash
export PATH=$PATH:~/.local/bin

# Chỉ định một cluster làm broker
subctl deploy-broker --kubeconfig ~/.kube/hub.kubeconfig

# Join cluster 1
subctl join broker-info.subm --kubeconfig ~/.kube/cluster-a.kubeconfig \
  --clusterid cluster-a

# Join cluster 2
subctl join broker-info.subm --kubeconfig ~/.kube/cluster-b.kubeconfig \
  --clusterid cluster-b

# Verify kết nối
subctl show all

# Test connectivity
subctl verify --kubeconfig ~/.kube/cluster-a.kubeconfig \
  --toconfig ~/.kube/cluster-b.kubeconfig \
  --only connectivity
```

```yaml
# Expose service qua Submariner ServiceExport
# manifests/multicluster-service.yaml
apiVersion: multicluster.x-k8s.io/v1alpha1
kind: ServiceExport
metadata:
  name: my-backend
  namespace: production
---
# Ở cluster B, truy cập qua ServiceImport tự động tạo:
# my-backend.production.svc.clusterset.local
```

### Step 5: Multi-cluster Ingress với ExternalDNS

```bash
# Cài ExternalDNS với Route53 (AWS)
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm install external-dns external-dns/external-dns \
  --set provider=aws \
  --set aws.region=us-east-1 \
  --set policy=upsert-only \
  --set registry=txt \
  --set txtOwnerId=my-cluster

# Ingress với ExternalDNS annotation
kubectl annotate ingress my-app \
  external-dns.alpha.kubernetes.io/hostname=app.example.com \
  external-dns.alpha.kubernetes.io/ttl=60

# Multi-cluster: DNS record trỏ tới nhiều IPs
# app.example.com → [cluster-us IP, cluster-eu IP]
# Route53 Latency-based routing → tự động chọn cluster gần nhất
```

### Step 6: Disaster Recovery Pattern

```bash
# Pattern: Active-Active với cross-cluster replication

# 1. Database replication (PostgreSQL với Patroni hoặc CloudNativePG)
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-primary
spec:
  instances: 3
  # Replica cluster ở region khác
  replica:
    enabled: false  # primary cluster
    source: postgres-primary
EOF

# 2. Velero cho backup/restore
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm install velero vmware-tanzu/velero \
  --set-file credentials.secretContents.cloud=./velero-credentials \
  --set configuration.provider=aws \
  --set configuration.backupStorageLocation.bucket=my-velero-backups \
  --set configuration.volumeSnapshotLocation.config.region=us-east-1

# Backup cluster state
velero backup create cluster-backup-$(date +%Y%m%d) \
  --include-namespaces production \
  --wait

# Restore ở cluster mới (DR scenario)
velero restore create --from-backup cluster-backup-20240101

# 3. RTO/RPO targets
# RPO (Recovery Point Objective): backup mỗi 1 giờ = max 1h data loss
# RTO (Recovery Time Objective): restore + DNS cutover = ~15 phút
```

### Step 7: Cost và Operational Considerations

```bash
# Kubecost — theo dõi cost per cluster
helm repo add cost-analyzer https://kubecost.github.io/cost-analyzer/
helm install cost-analyzer cost-analyzer/cost-analyzer \
  --namespace kubecost \
  --create-namespace \
  --set kubecostToken="your-token"

# Xem cost breakdown
kubectl port-forward svc/cost-analyzer-cost-analyzer 9090 -n kubecost
# http://localhost:9090

# Goldilocks — right-size resource requests
kubectl apply -f https://github.com/FairwindsOps/goldilocks/releases/latest/download/goldilocks.yaml
kubectl label namespace production goldilocks.fairwinds.com/enabled=true
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# Kiểm tra tất cả clusters healthy
for ctx in hub spoke-dev spoke-prod; do
  echo "=== Context: $ctx ==="
  kubectl --context=$ctx get nodes
  kubectl --context=$ctx get pods -A --field-selector=status.phase!=Running 2>/dev/null | head -5
done

# Kiểm tra CAPI clusters
kubectl --context=hub get clusters -A
kubectl --context=hub get machines -A
kubectl --context=hub get machinesets -A

# Test cross-cluster connectivity (nếu dùng Submariner)
subctl show connections

# Verify ArgoCD quản lý tất cả clusters
argocd cluster list
argocd app list

# Kiểm tra DNS records
dig +short app.example.com
nslookup app.example.com
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xóa workload clusters qua CAPI (declarative)
kubectl delete cluster workload-cluster-1 -n default

# Xóa Submariner
subctl unexport service my-backend -n production
# Uninstall submariner components
kubectl delete namespace submariner-operator

# Xóa local kind clusters
kind delete cluster --name cluster-hub
kind delete cluster --name cluster-spoke

# Clean up kubeconfig
kubectl config delete-context hub
kubectl config delete-context spoke-prod
kubectl config delete-cluster kind-cluster-hub
kubectl config delete-cluster kind-cluster-spoke

# Remove merged kubeconfig
rm ~/.kube/merged-config
```

---

## 💡 Tips & Gotchas

### ⚠️ Thách thức Multi-cluster

1. **mTLS và network policies** không apply cross-cluster → dùng Istio mesh hoặc Submariner
2. **Shared secrets** giữa clusters → dùng External Secrets Operator + HashiCorp Vault
3. **Monitoring aggregation** → Thanos hoặc Grafana Mimir để federate Prometheus
4. **Log aggregation** → Fluentd/Vector → ElasticSearch/Loki centralized
5. **Image registry** → Dùng một registry chung, hoặc replicate với Harbor

### 💡 Tool Ecosystem

| Use Case | Tools |
|----------|-------|
| Context switching | `kubectx`, `kubie`, `kubeswitch` |
| Multi-cluster deploy | ArgoCD, Flux |
| Service mesh | Istio multi-cluster, Linkerd |
| Network connectivity | Submariner, Cilium Cluster Mesh |
| Federation | KubeEdge (edge), Admiralty (virtual nodes) |
| Backup/DR | Velero |
| Cost | Kubecost |
| Provisioning | Cluster API, Crossplane |

### ⚠️ Cần tránh

- Không share etcd giữa các clusters
- Không dùng kubectl context nhầm cluster (→ dùng kubectx + PS1 prompt)
- Không deploy management tools lên workload cluster
- Kiểm tra RBAC trước khi mở cross-cluster network

---

## 📚 Tham khảo (References)

- [Cluster API Docs](https://cluster-api.sigs.k8s.io/)
- [Submariner](https://submariner.io/)
- [ArgoCD Multi-cluster](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [Velero](https://velero.io/docs/)
- [Kubecost](https://www.kubecost.com/)
- [Multi-cluster Networking SIG](https://github.com/kubernetes/community/tree/master/sig-multicluster)

---

## 🔗 Next Lab

➡️ **[Lab 36 — Full CI/CD Pipeline](../lab-36-cicd-pipeline/README.md)**

Xây dựng pipeline CI/CD end-to-end hoàn chỉnh: GitHub Actions → Docker Build → Helm → ArgoCD → Canary Deployment.
