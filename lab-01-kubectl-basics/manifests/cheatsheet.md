# kubectl Command Cheatsheet

> Quick reference cho tất cả lệnh kubectl thường dùng trong Kubernetes daily workflow.

---

## 🔧 Cluster & Config

```bash
kubectl version                          # Client + Server version
kubectl version --client                 # Chỉ client version
kubectl cluster-info                     # Cluster endpoint info
kubectl cluster-info dump                # Full cluster debug dump

kubectl config view                      # Xem kubeconfig
kubectl config current-context           # Context hiện tại
kubectl config get-contexts              # Liệt kê tất cả contexts
kubectl config use-context <name>        # Chuyển context
kubectl config set-context --current \
  --namespace=<ns>                       # Đổi default namespace
kubectl config get-clusters              # Liệt kê clusters
kubectl config get-users                 # Liệt kê users
```

---

## 📦 Nodes

```bash
kubectl get nodes                        # Liệt kê nodes
kubectl get nodes -o wide                # Thêm IP, OS, runtime info
kubectl describe node <name>             # Chi tiết node
kubectl top nodes                        # CPU/Memory usage (cần metrics-server)
kubectl cordon <node>                    # Ngừng schedule pods lên node
kubectl uncordon <node>                  # Cho phép schedule trở lại
kubectl drain <node> --ignore-daemonsets # Evict pods khỏi node (maintenance)
kubectl taint node <node> key=val:NoSchedule  # Thêm taint
```

---

## 🗂️ Namespaces

```bash
kubectl get ns                           # Liệt kê namespaces
kubectl create ns <name>                 # Tạo namespace
kubectl delete ns <name>                 # Xóa namespace (và TẤT CẢ resources)
kubectl describe ns <name>               # Chi tiết namespace
```

---

## 🐳 Pods

```bash
# Get
kubectl get pods                         # Pods trong default namespace
kubectl get pods -n <ns>                 # Pods trong namespace cụ thể
kubectl get pods -A                      # Pods trong TẤT CẢ namespaces
kubectl get pods -o wide                 # Thêm NODE, IP info
kubectl get pods -w                      # Watch mode (real-time update)
kubectl get pods --show-labels           # Hiện labels
kubectl get pods -l app=nginx            # Filter by label
kubectl get pods -o yaml                 # Output YAML
kubectl get pods -o json                 # Output JSON
kubectl get pods -o jsonpath='...'       # JSONPath query

# Run & Create
kubectl run <name> --image=<img>         # Tạo pod nhanh
kubectl run <name> --image=<img> \
  --dry-run=client -o yaml               # Preview YAML, không deploy

# Describe & Debug
kubectl describe pod <name>              # Chi tiết pod (events, conditions)
kubectl logs <pod>                       # Xem logs
kubectl logs <pod> -c <container>        # Logs của container cụ thể
kubectl logs <pod> -f                    # Follow logs (tail -f)
kubectl logs <pod> --previous            # Logs của pod trước đó (đã crash)
kubectl logs <pod> --tail=50             # 50 dòng cuối
kubectl logs <pod> --since=1h            # Logs trong 1 giờ gần nhất

# Execute
kubectl exec <pod> -- ls /              # Chạy command trong pod
kubectl exec -it <pod> -- /bin/sh       # Interactive shell
kubectl exec -it <pod> -c <cnt> -- sh  # Shell vào container cụ thể

# Port forward
kubectl port-forward pod/<name> 8080:80  # Local:PodPort

# Copy files
kubectl cp <pod>:/path/file ./local      # Copy từ pod về local
kubectl cp ./local <pod>:/path/file      # Copy từ local lên pod

# Delete
kubectl delete pod <name>               # Xóa pod
kubectl delete pod <name> --grace-period=0 --force  # Xóa ngay lập tức
```

---

## 🚀 Deployments

```bash
kubectl get deployments                  # Liệt kê deployments
kubectl get deploy -n <ns>              # Trong namespace cụ thể
kubectl describe deploy <name>          # Chi tiết
kubectl create deploy <name> \
  --image=<img> --replicas=3           # Tạo deployment
kubectl scale deploy <name> \
  --replicas=5                          # Scale
kubectl rollout status deploy/<name>    # Xem trạng thái rollout
kubectl rollout history deploy/<name>   # Lịch sử rollout
kubectl rollout undo deploy/<name>      # Rollback
kubectl rollout undo deploy/<name> \
  --to-revision=2                       # Rollback về revision cụ thể
kubectl set image deploy/<name> \
  container=new-image:tag               # Update image
kubectl delete deploy <name>            # Xóa deployment
```

---

## 🌐 Services

```bash
kubectl get svc                          # Liệt kê services
kubectl describe svc <name>             # Chi tiết service
kubectl expose pod <pod> \
  --port=80 --target-port=8080          # Tạo service từ pod
kubectl expose deploy <deploy> \
  --type=LoadBalancer --port=80         # Expose deployment
kubectl delete svc <name>               # Xóa service
kubectl port-forward svc/<name> 8080:80  # Port forward từ service
```

---

## 📋 ConfigMaps & Secrets

```bash
# ConfigMap
kubectl get configmaps                   # Liệt kê
kubectl get cm <name> -o yaml           # Xem nội dung
kubectl create configmap <name> \
  --from-literal=key=value              # Tạo từ literal
kubectl create configmap <name> \
  --from-file=config.properties         # Tạo từ file
kubectl describe cm <name>              # Chi tiết

# Secret
kubectl get secrets                     # Liệt kê
kubectl create secret generic <name> \
  --from-literal=password=secret123     # Tạo generic secret
kubectl create secret docker-registry \
  regcred \
  --docker-server=<server> \
  --docker-username=<user> \
  --docker-password=<pass>              # Docker registry secret
kubectl get secret <name> -o yaml      # Xem (base64 encoded)
# Decode secret value:
kubectl get secret <name> \
  -o jsonpath='{.data.password}' | base64 -d
```

---

## 📊 Apply, Create, Delete (Declarative)

```bash
kubectl apply -f file.yaml               # Apply (create or update)
kubectl apply -f ./manifests/            # Apply toàn bộ thư mục
kubectl apply -f https://url/file.yaml   # Apply từ URL
kubectl create -f file.yaml              # Create (lỗi nếu đã tồn tại)
kubectl delete -f file.yaml              # Xóa resources trong file
kubectl diff -f file.yaml                # So sánh file vs cluster state
kubectl replace -f file.yaml             # Replace resource
kubectl replace -f file.yaml --force     # Delete & recreate
```

---

## 🔍 Labels & Annotations

```bash
kubectl label pod <name> env=prod         # Thêm label
kubectl label pod <name> env-             # Xóa label
kubectl annotate pod <name> note="test"   # Thêm annotation
kubectl get pods -l env=prod             # Filter by label
kubectl get pods -l 'env in (prod,staging)' # Filter nhiều values
kubectl get pods -l 'env!=dev'           # Negative filter
```

---

## 📈 Resource Quotas & Limits

```bash
kubectl get resourcequota -n <ns>        # Xem quotas
kubectl describe resourcequota -n <ns>   # Chi tiết quota usage
kubectl get limitrange -n <ns>           # Xem limit ranges
```

---

## 🔄 Events & Troubleshooting

```bash
kubectl get events                        # Xem events
kubectl get events -n <ns>              # Events trong namespace
kubectl get events \
  --sort-by='.lastTimestamp'             # Sort theo thời gian
kubectl get events \
  --field-selector reason=Failed         # Filter events
kubectl describe pod <name>             # Xem events của pod (cuối output)

# Debug pod đang pending/crashlooping
kubectl describe pod <name> | grep -A 10 Events
kubectl logs <pod> --previous           # Logs lần crash trước
```

---

## 🎯 Output Formatting

```bash
# Output formats
-o yaml          # YAML format
-o json          # JSON format  
-o wide          # Thêm columns
-o name          # Chỉ tên resource
-o jsonpath='...'  # JSONPath expression
-o custom-columns=NAME:.metadata.name,STATUS:.status.phase

# Ví dụ JSONPath
kubectl get pods -o jsonpath='{.items[*].metadata.name}'
kubectl get pod <name> -o jsonpath='{.status.podIP}'
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.nodeInfo.osImage}{"\n"}{end}'
```

---

## 🏃 Imperative vs Declarative Quick Reference

| Action | Imperative | Declarative |
|--------|-----------|-------------|
| Create pod | `kubectl run nginx --image=nginx` | `kubectl apply -f pod.yaml` |
| Create deploy | `kubectl create deploy nginx --image=nginx` | `kubectl apply -f deploy.yaml` |
| Create service | `kubectl expose deploy nginx --port=80` | `kubectl apply -f svc.yaml` |
| Scale | `kubectl scale deploy nginx --replicas=3` | Edit yaml + apply |
| Update image | `kubectl set image deploy/nginx nginx=nginx:1.25` | Edit yaml + apply |
| Delete | `kubectl delete pod nginx` | `kubectl delete -f pod.yaml` |

---

## 🔑 Keyboard Shortcuts & Power Tips

```bash
# Xem và edit resource trực tiếp
kubectl edit pod <name>           # Mở editor để edit live

# Generate YAML templates (dry-run)
kubectl run nginx --image=nginx --dry-run=client -o yaml > pod.yaml
kubectl create deploy nginx --image=nginx --dry-run=client -o yaml > deploy.yaml
kubectl create service clusterip nginx --tcp=80:80 --dry-run=client -o yaml > svc.yaml

# Xóa nhiều resources cùng lúc
kubectl delete pod pod1 pod2 pod3
kubectl delete pods -l app=nginx
kubectl delete all -l app=nginx     # Xóa pods, services, deployments với label

# Alias patterns (add to ~/.zshrc)
alias k='kubectl'
alias kg='kubectl get'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias ke='kubectl exec -it'
alias ka='kubectl apply -f'
alias kdel='kubectl delete'
```

---

*Cheatsheet này được tạo cho Lab 01 — kubectl Basics & Cluster Info*
*Cập nhật: 2024 | Kubernetes v1.28+*
