# Lab 33 — Helm Package Manager

## 🎯 Mục tiêu (Objectives)

Sau khi hoàn thành lab này, bạn sẽ:
- Hiểu kiến trúc và các khái niệm cốt lõi của Helm (Chart, Repository, Release, Revision)
- Tạo và cấu trúc một Helm Chart hoàn chỉnh từ đầu
- Thành thạo Helm template functions: `toYaml`, `indent`, `quote`, `default`, `if/else`, `range`, `with`
- Sử dụng Helm Hooks (`pre-install`, `post-install`, `pre-upgrade`) cho lifecycle management
- Viết Helm tests để xác minh deployment
- Sử dụng Helm plugin ecosystem (`helm-diff`, `helm-secrets`)
- Publish chart lên OCI registry (GHCR, ECR)
- Quản lý dependency charts (sub-charts)

---

## 📋 Prerequisites

- Lab 01–32 đã hoàn thành (đặc biệt Ingress, ConfigMap, Secrets)
- `helm` v3.12+ installed: `brew install helm`
- `kubectl` configured với cluster đang chạy
- Docker Hub hoặc GHCR account (để push chart)
- `git` installed

```bash
# Verify Helm installation
helm version
# Output: version.BuildInfo{Version:"v3.x.x", ...}

# Add useful plugins
helm plugin install https://github.com/databus23/helm-diff
helm plugin list
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Helm là gì?

Helm là **package manager cho Kubernetes**, giúp đóng gói, cấu hình, và deploy ứng dụng phức tạp.

```
┌─────────────────────────────────────────────────────────┐
│                    HELM ARCHITECTURE                     │
│                                                         │
│   Developer           Helm CLI           Kubernetes     │
│   ─────────           ────────           ──────────     │
│                                                         │
│   Chart ──────────► helm install ──────► API Server    │
│   (templates +        helm upgrade       (creates K8s   │
│    values.yaml)       helm rollback       resources)    │
│                       helm uninstall                    │
│                                                         │
│   Repository                             Release Store  │
│   ─────────────                          ────────────   │
│   chart.museum        helm repo add       Secrets in    │
│   OCI registry        helm repo update    namespace     │
│   artifact hub                                          │
└─────────────────────────────────────────────────────────┘
```

### 4 Khái niệm cốt lõi

| Khái niệm | Mô tả | Ví dụ |
|-----------|-------|-------|
| **Chart** | Package chứa K8s manifests + templates | `my-webapp-1.0.0.tgz` |
| **Repository** | Nơi lưu trữ charts | `https://charts.bitnami.com` |
| **Release** | Một instance của chart được install | `my-webapp-production` |
| **Revision** | Phiên bản của một release sau mỗi upgrade | Revision 1→2→3 |

### Cấu trúc Helm Chart

```
my-webapp/
├── Chart.yaml          # Chart metadata (name, version, dependencies)
├── values.yaml         # Default configuration values
├── charts/             # Dependency charts (sub-charts)
├── templates/          # Template files → K8s manifests
│   ├── _helpers.tpl    # Template partials/helpers (không render thành file)
│   ├── NOTES.txt       # Post-install notes hiển thị cho user
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── configmap.yaml
│   ├── hpa.yaml
│   └── tests/
│       └── test-connection.yaml
└── .helmignore         # Giống .gitignore, bỏ qua files khi đóng gói
```

### Template Functions quan trọng

```yaml
# toYaml + nindent: render nested YAML structures
resources:
  {{- toYaml .Values.resources | nindent 4 }}

# default: giá trị mặc định nếu giá trị rỗng
image: {{ .Values.image.tag | default "latest" | quote }}

# if/else: conditional rendering
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
...
{{- end }}

# range: lặp qua list hoặc map
{{- range .Values.env }}
- name: {{ .name }}
  value: {{ .value | quote }}
{{- end }}

# with: scope tạm thời
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 8 }}
{{- end }}
```

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Tạo Helm Chart từ đầu

```bash
# Tạo scaffold chart
helm create my-webapp

# Xem cấu trúc được tạo ra
tree my-webapp/
```

Xóa các file mẫu và dùng chart của chúng ta:

```bash
# Xóa templates mặc định
rm -rf my-webapp/templates/*
rm my-webapp/values.yaml

# Sử dụng các file trong lab này
ls manifests/my-webapp/templates/
```

### Step 2: Kiểm tra và Lint Chart

```bash
# Lint chart để phát hiện lỗi
helm lint manifests/my-webapp/

# Dry-run để xem output YAML
helm template my-webapp manifests/my-webapp/ \
  --values manifests/my-webapp/values.yaml

# Dry-run với custom values
helm template my-webapp manifests/my-webapp/ \
  --set image.tag=v2.0.0 \
  --set replicaCount=3 \
  --set ingress.enabled=true \
  --set ingress.host=myapp.example.com
```

### Step 3: Install Chart lần đầu

```bash
# Tạo namespace
kubectl create namespace my-webapp

# Install chart
helm install my-webapp manifests/my-webapp/ \
  --namespace my-webapp \
  --values manifests/my-webapp/values.yaml \
  --set image.tag=nginx:1.25 \
  --wait \
  --timeout 5m

# Kiểm tra release
helm list -n my-webapp
helm status my-webapp -n my-webapp
```

### Step 4: Upgrade và Rollback

```bash
# Upgrade release với values mới
helm upgrade my-webapp manifests/my-webapp/ \
  --namespace my-webapp \
  --set replicaCount=3 \
  --set image.tag=nginx:1.26 \
  --wait

# Xem lịch sử revisions
helm history my-webapp -n my-webapp

# Output:
# REVISION  UPDATED       STATUS      CHART          APP VERSION  DESCRIPTION
# 1         ...           superseded  my-webapp-1.0  1.0.0        Install complete
# 2         ...           deployed    my-webapp-1.0  1.0.0        Upgrade complete

# Rollback về revision trước
helm rollback my-webapp 1 --namespace my-webapp --wait

# Rollback về revision ngay trước đó
helm rollback my-webapp --namespace my-webapp
```

### Step 5: Helm Diff Plugin (xem thay đổi trước khi apply)

```bash
# Cài đặt plugin nếu chưa có
helm plugin install https://github.com/databus23/helm-diff

# Xem diff trước khi upgrade
helm diff upgrade my-webapp manifests/my-webapp/ \
  --namespace my-webapp \
  --set replicaCount=5

# Output sẽ hiển thị từng dòng thay đổi như git diff
```

### Step 6: Helm Hooks

Hooks cho phép chạy Jobs vào các điểm cụ thể trong vòng đời release:

```yaml
# templates/pre-install-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "my-webapp.fullname" . }}-pre-install
  annotations:
    "helm.sh/hook": pre-install        # Chạy TRƯỚC khi install
    "helm.sh/hook-weight": "-5"        # Thứ tự thực thi (nhỏ hơn = chạy trước)
    "helm.sh/hook-delete-policy": hook-succeeded  # Xóa sau khi thành công
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: pre-install
        image: busybox
        command: ['sh', '-c', 'echo "Running pre-install migration..."']
```

**Các hook annotations:**
- `pre-install` — trước khi resources được tạo
- `post-install` — sau khi tất cả resources đã tạo
- `pre-upgrade` — trước khi upgrade
- `post-upgrade` — sau khi upgrade hoàn tất
- `pre-delete` — trước khi xóa release
- `post-delete` — sau khi xóa
- `pre-rollback`, `post-rollback`
- `test` — chạy bởi `helm test`

### Step 7: Helm Test

```bash
# Chạy tests sau khi install
helm test my-webapp -n my-webapp

# Xem pod test (tạo ra từ templates/tests/)
kubectl get pods -n my-webapp -l "helm.sh/chart=my-webapp"
```

Template test file (`templates/tests/test-connection.yaml`):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: "{{ include "my-webapp.fullname" . }}-test-connection"
  annotations:
    "helm.sh/hook": test
spec:
  restartPolicy: Never
  containers:
  - name: wget
    image: busybox
    command: ['wget', '--spider', 'http://{{ include "my-webapp.fullname" . }}:{{ .Values.service.port }}']
```

### Step 8: Dependency Charts

```bash
# Chart.yaml khai báo dependencies
cat manifests/my-webapp/Chart.yaml

# Download dependencies
helm dependency update manifests/my-webapp/

# List dependencies
helm dependency list manifests/my-webapp/

# Ví dụ: thêm PostgreSQL và Redis làm sub-chart
```

```yaml
# Trong Chart.yaml:
dependencies:
  - name: postgresql
    version: "12.x.x"
    repository: "https://charts.bitnami.com/bitnami"
    condition: postgresql.enabled    # Chỉ enable nếu values cho phép
  - name: redis
    version: "17.x.x"
    repository: "https://charts.bitnami.com/bitnami"
    condition: redis.enabled
```

### Step 9: Publish Chart lên OCI Registry (GHCR)

```bash
# Login vào GitHub Container Registry
echo $GITHUB_TOKEN | helm registry login ghcr.io -u USERNAME --password-stdin

# Package chart
helm package manifests/my-webapp/
# Output: my-webapp-1.0.0.tgz

# Push lên OCI registry
helm push my-webapp-1.0.0.tgz oci://ghcr.io/USERNAME/helm-charts

# Pull và install từ OCI registry
helm install my-app oci://ghcr.io/USERNAME/helm-charts/my-webapp \
  --version 1.0.0

# Inspect chart từ OCI
helm show values oci://ghcr.io/USERNAME/helm-charts/my-webapp --version 1.0.0
```

### Step 10: Helm Repository tự host (ChartMuseum)

```bash
# Deploy ChartMuseum trên cluster
helm repo add chartmuseum https://chartmuseum.github.io/charts
helm install chartmuseum chartmuseum/chartmuseum \
  --set env.open.STORAGE=local \
  --set persistence.enabled=true

# Upload chart lên ChartMuseum
curl --data-binary "@my-webapp-1.0.0.tgz" http://localhost:8080/api/charts

# Thêm repo và install
helm repo add myrepo http://localhost:8080
helm repo update
helm search repo myrepo/my-webapp
helm install my-app myrepo/my-webapp
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# Kiểm tra release status
helm list -A
helm status my-webapp -n my-webapp

# Kiểm tra K8s resources được tạo
kubectl get all -n my-webapp -l "app.kubernetes.io/instance=my-webapp"

# Kiểm tra values đang dùng
helm get values my-webapp -n my-webapp
helm get values my-webapp -n my-webapp --all   # Bao gồm default values

# Kiểm tra manifest đang deploy
helm get manifest my-webapp -n my-webapp

# Chạy tests
helm test my-webapp -n my-webapp --logs

# Verify hook đã chạy
kubectl get jobs -n my-webapp
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Uninstall release (xóa tất cả K8s resources)
helm uninstall my-webapp -n my-webapp

# Verify không còn resources
kubectl get all -n my-webapp

# Xóa namespace
kubectl delete namespace my-webapp

# Xóa local chart package
rm -f my-webapp-*.tgz

# Remove repo (nếu đã add)
helm repo remove bitnami
```

---

## 💡 Tips & Gotchas

### ⚠️ Lỗi phổ biến

1. **`helm upgrade --install` pattern** — dùng một lệnh cho cả install và upgrade:
   ```bash
   # Idempotent: install nếu chưa có, upgrade nếu đã có
   helm upgrade --install my-webapp manifests/my-webapp/ \
     --namespace my-webapp --create-namespace
   ```

2. **Values precedence** (thứ tự ưu tiên, cao → thấp):
   ```
   --set flag > -f custom-values.yaml > values.yaml (chart default)
   ```

3. **`nindent` vs `indent`**:
   ```yaml
   # nindent = newline + indent (dùng khi bắt đầu block)
   {{- toYaml .Values.resources | nindent 4 }}
   # indent = chỉ indent (không có newline đầu)
   {{- toYaml .Values.resources | indent 4 }}
   ```

4. **Quản lý secrets với helm-secrets**:
   ```bash
   helm plugin install https://github.com/jkroepke/helm-secrets
   # Sử dụng với SOPS để encrypt values.yaml
   helm secrets upgrade my-webapp . -f secrets.yaml
   ```

5. **Chart version vs App version**:
   - `version` trong Chart.yaml: phiên bản của Helm chart
   - `appVersion`: phiên bản của ứng dụng bên trong chart

6. **--atomic flag** cho production upgrades:
   ```bash
   # Tự động rollback nếu upgrade fail
   helm upgrade my-webapp . --atomic --timeout 5m
   ```

### 💡 Best Practices Production

- Luôn sử dụng `--wait` và `--timeout` trong CI/CD
- Pin dependency chart versions (không dùng `>=`)
- Sử dụng `helm diff` trước mỗi upgrade
- Lưu custom values trong Git (GitOps)
- Đặt resource limits trong values.yaml (không hardcode trong templates)
- Sử dụng `.helmignore` để tránh leak secrets vào chart package

---

## 📚 Tham khảo (References)

- [Helm Official Docs](https://helm.sh/docs/)
- [Helm Chart Best Practices](https://helm.sh/docs/chart_best_practices/)
- [Artifact Hub](https://artifacthub.io/) — tìm kiếm public charts
- [helm-diff plugin](https://github.com/databus23/helm-diff)
- [helm-secrets plugin](https://github.com/jkroepke/helm-secrets)
- [ChartMuseum](https://chartmuseum.com/)

---

## 🔗 Next Lab

➡️ **[Lab 34 — GitOps with ArgoCD](../lab-34-gitops-argocd/README.md)**

Triển khai GitOps workflow với ArgoCD, quản lý Helm charts theo phong cách khai báo.
