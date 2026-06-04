# Lab 09 — Job & CronJob

## 🎯 Mục tiêu (Objectives)

Sau lab này bạn sẽ hiểu và làm được:
- Tạo **Job** để chạy tác vụ một lần (batch processing)
- Hiểu các loại Job: **single**, **parallel với fixed completions**, **work queue**
- Cấu hình `completions`, `parallelism`, `backoffLimit`, `activeDeadlineSeconds`
- Tạo **CronJob** để chạy Job theo lịch (cron expression)
- Cấu hình `concurrencyPolicy`, `successfulJobsHistoryLimit`, `failedJobsHistoryLimit`
- Phân biệt khi nào dùng Job, khi nào dùng CronJob

---

## 📋 Prerequisites

- Đã hoàn thành Lab 05–08
- Cluster Kubernetes đang hoạt động
- Hiểu cơ bản về Pod

```bash
kubectl cluster-info
kubectl get nodes
```

---

## 🧠 Lý thuyết nhanh (Quick Theory)

### Job là gì?

**Job** tạo một hoặc nhiều Pods và đảm bảo rằng một số lượng cụ thể chạy **thành công đến hoàn thành** (exit code 0). Không giống Pod bình thường, Job không restart mãi mãi — nó có một mục tiêu hoàn thành.

```
Job Types:

1. Single Job (completions=1, parallelism=1):
   ┌──────┐   exit 0   → Job SUCCEEDED ✅
   │ Pod  │
   └──────┘   exit 1   → Retry (backoffLimit lần)

2. Fixed Completions (completions=5, parallelism=2):
   ┌──────┐ ┌──────┐         2 pods chạy song song
   │ Pod1 │ │ Pod2 │
   └──────┘ └──────┘
   ┌──────┐ ┌──────┐         Khi 2 done → 2 cái mới
   │ Pod3 │ │ Pod4 │
   └──────┘ └──────┘
   ┌──────┐                  Pod cuối cùng (5/5)
   │ Pod5 │
   └──────┘  → Job SUCCEEDED khi đủ 5 completions ✅

3. Work Queue (completions=unset, parallelism=3):
   ┌──────┐ ┌──────┐ ┌──────┐   3 workers lấy task từ queue
   │ Pod1 │ │ Pod2 │ │ Pod3 │
   └──────┘ └──────┘ └──────┘   Job done khi 1 pod exit 0 và
                                  không còn task nào trong queue
```

### Các tham số quan trọng của Job

| Tham số | Mặc định | Mô tả |
|---------|---------|-------|
| `completions` | 1 | Số lần Pod phải hoàn thành thành công |
| `parallelism` | 1 | Số Pod chạy song song tối đa |
| `backoffLimit` | 6 | Số lần retry khi Pod fail |
| `activeDeadlineSeconds` | - | Timeout toàn bộ Job (giây) |
| `ttlSecondsAfterFinished` | - | Tự động xoá Job sau N giây khi xong |

### CronJob Schedule Syntax

```
┌───────────── phút (0-59)
│ ┌───────────── giờ (0-23)
│ │ ┌───────────── ngày trong tháng (1-31)
│ │ │ ┌───────────── tháng (1-12)
│ │ │ │ ┌───────────── ngày trong tuần (0-6, 0=Chủ nhật)
│ │ │ │ │
* * * * *

Ví dụ:
0 * * * *      → Mỗi giờ (vào phút 0)
0 0 * * *      → Hàng ngày lúc nửa đêm
0 9 * * 1-5    → Thứ 2-6, 9:00 sáng
*/5 * * * *    → Mỗi 5 phút
0 0 1 * *      → Ngày 1 hàng tháng
* * * * *      → Mỗi phút (test only!)
```

### concurrencyPolicy

```
Allow (default):
  Time:  0min   1min   2min   3min
  Job:   [J1]   [J1][J2]    [J1][J2][J3]
  → Cho phép nhiều Jobs chạy cùng lúc (nếu previous chưa xong)

Forbid:
  Time:  0min   1min   2min   3min
  Job:   [J1]   [J1]   [J1]   [J1][J2]  (J2 chờ J1 xong)
  → Bỏ qua schedule nếu Job trước chưa xong

Replace:
  Time:  0min   1min   2min   3min
  Job:   [J1]   [J2*]  [J3*]  [J4*]     (* xoá previous)
  → Kill và replace Job cũ bằng Job mới
```

---

## 🛠️ Thực hành (Hands-on)

### Step 1: Setup namespace

```bash
kubectl create namespace lab09
kubectl config set-context --current --namespace=lab09
```

### Step 2: Chạy Job tính Pi

```bash
kubectl apply -f manifests/job-pi-calculator.yaml

# Watch Job status
kubectl get job job-pi-calculator -n lab09 -w
# NAME               COMPLETIONS   DURATION   AGE
# job-pi-calculator  0/1                      1s
# job-pi-calculator  1/1           8s         8s  ← Job completed!
```

Xem output:
```bash
# Lấy pod name của job
POD_NAME=$(kubectl get pods -n lab09 -l job-name=job-pi-calculator -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $POD_NAME"

# Xem kết quả tính Pi
kubectl logs $POD_NAME -n lab09
# 3.14159265358979323846264338327950288419716939937510...
```

Xem trạng thái Job chi tiết:
```bash
kubectl describe job job-pi-calculator -n lab09
```

### Step 3: Job với Parallel execution

```bash
kubectl apply -f manifests/job-parallel.yaml

# Watch nhiều pods chạy song song
kubectl get pods -n lab09 -l job-name=job-parallel -w
```

```bash
# Xem progress (completions)
kubectl get job job-parallel -n lab09
# COMPLETIONS sẽ tăng dần: 0/5, 1/5, 2/5, ... 5/5
```

```bash
# Xem logs của tất cả pods
kubectl logs -l job-name=job-parallel -n lab09 --prefix
```

### Step 4: Thử nghiệm backoffLimit — Job Retry

Tạo Job cố tình fail để xem retry:
```bash
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: job-fail-test
  namespace: lab09
spec:
  backoffLimit: 3   # Thử lại tối đa 3 lần
  template:
    spec:
      restartPolicy: Never   # KHÔNG restart container, tạo pod MỚI
      containers:
      - name: fail
        image: busybox:1.35
        command: ["sh", "-c", "echo 'I am failing!' && exit 1"]
        resources:
          limits:
            cpu: "50m"
            memory: "32Mi"
EOF

# Watch pods được tạo lại (sẽ có 4 pods: 1 + 3 retries)
kubectl get pods -n lab09 -l job-name=job-fail-test -w
```

```bash
# Xem Job status sau khi fail hết retry
kubectl describe job job-fail-test -n lab09 | grep -A 5 "Conditions:"
# Type: Failed
# Reason: BackoffLimitExceeded
```

### Step 5: activeDeadlineSeconds — Job Timeout

```bash
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: job-timeout
  namespace: lab09
spec:
  activeDeadlineSeconds: 10   # Timeout sau 10 giây
  backoffLimit: 5
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: sleeper
        image: busybox:1.35
        command: ["sh", "-c", "echo 'Starting...'; sleep 30; echo 'Done'"]
        resources:
          limits:
            cpu: "50m"
            memory: "32Mi"
EOF

# Sau 10 giây, Job sẽ bị terminate!
kubectl get job job-timeout -n lab09 -w
# Sau ~10s:
# job-timeout   0/1   10s   11s
# kubectl describe sẽ cho thấy: reason: DeadlineExceeded
```

### Step 6: Tạo CronJob — Simulated Backup

```bash
kubectl apply -f manifests/cronjob-backup.yaml

# Xem CronJob
kubectl get cronjob -n lab09
# NAME             SCHEDULE    SUSPEND   ACTIVE   LAST SCHEDULE   AGE
# backup-cronjob   * * * * *   False     0        <none>          5s

# Chờ 1 phút — CronJob sẽ tạo Job mới
kubectl get jobs -n lab09 -w
```

Sau 1 phút, Job đầu tiên được tạo:
```bash
# Xem các Jobs được tạo bởi CronJob
kubectl get jobs -n lab09

# Xem logs của backup job
BACKUP_POD=$(kubectl get pods -n lab09 -l app=backup -o jsonpath='{.items[0].metadata.name}')
kubectl logs $BACKUP_POD -n lab09
```

### Step 7: Tạo CronJob — Report Generator

```bash
kubectl apply -f manifests/cronjob-report.yaml

# Xem tất cả CronJobs
kubectl get cronjob -n lab09
```

### Step 8: Kiểm tra concurrencyPolicy

```bash
# Pause CronJob để ngăn tạo jobs mới
kubectl patch cronjob backup-cronjob -n lab09 -p '{"spec":{"suspend":true}}'

# Resume
kubectl patch cronjob backup-cronjob -n lab09 -p '{"spec":{"suspend":false}}'
```

Tạo Job thủ công từ CronJob (để test ngay không cần chờ schedule):
```bash
kubectl create job manual-backup --from=cronjob/backup-cronjob -n lab09

kubectl get jobs -n lab09
kubectl logs -l job-name=manual-backup -n lab09
```

### Step 9: Quản lý history (successfulJobsHistoryLimit)

```bash
# Xem history của các Jobs (cả completed và failed)
kubectl get jobs -n lab09 --sort-by='.metadata.creationTimestamp'

# CronJob tự động cleanup jobs cũ theo successfulJobsHistoryLimit
kubectl describe cronjob backup-cronjob -n lab09 | grep -A 5 "Successful Job"
```

### Step 10: ttlSecondsAfterFinished — Auto cleanup

```bash
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: job-auto-cleanup
  namespace: lab09
spec:
  # Tự động xoá Job (và pods) sau 60 giây khi hoàn thành
  ttlSecondsAfterFinished: 60
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: worker
        image: busybox:1.35
        command: ["sh", "-c", "echo 'Task done!'; exit 0"]
        resources:
          limits:
            cpu: "50m"
            memory: "32Mi"
EOF

kubectl get job job-auto-cleanup -n lab09 -w
# Sau khi completed + 60s, Job sẽ tự biến mất
```

---

## ✅ Kiểm tra kết quả (Verification)

```bash
# 1. Xem tất cả Jobs
kubectl get jobs -n lab09

# 2. Xem tất cả CronJobs
kubectl get cronjob -n lab09

# 3. Kiểm tra status của từng Job
kubectl get jobs -n lab09 -o custom-columns=\
NAME:.metadata.name,\
COMPLETIONS:.status.completions,\
DURATION:.status.completionTime,\
FAILED:.status.failed

# 4. Xem pods của tất cả Jobs
kubectl get pods -n lab09

# 5. Xem logs của Pi calculator
kubectl logs -l job-name=job-pi-calculator -n lab09

# 6. Xem history của CronJob
kubectl describe cronjob backup-cronjob -n lab09

# 7. Tổng quan
kubectl get all -n lab09
```

---

## 🧹 Dọn dẹp (Cleanup)

```bash
# Xoá tất cả Jobs (và pods của chúng)
kubectl delete jobs --all -n lab09

# Xoá tất cả CronJobs
kubectl delete cronjobs --all -n lab09

# Hoặc xoá toàn bộ namespace
kubectl delete namespace lab09

kubectl config set-context --current --namespace=default
```

---

## 💡 Tips & Gotchas

1. **`restartPolicy` trong Job phải là `Never` hoặc `OnFailure`** (không phải `Always` như Pod thông thường):
   - `Never`: Tạo pod MỚI khi fail (có thể có nhiều pods failed)
   - `OnFailure`: Restart container trong CÙNG pod khi fail

2. **`backoffLimit` + `restartPolicy: Never`**: Kubernetes tạo pod mới mỗi lần retry → có thể tốn resources. Giám sát số pods failed.

3. **CronJob timezone**: Mặc định dùng timezone của kube-controller-manager. Có thể set timezone:
   ```yaml
   spec:
     timeZone: "Asia/Ho_Chi_Minh"  # K8s 1.27+
     schedule: "0 9 * * 1-5"
   ```

4. **Missed schedules**: Nếu CronJob miss > 100 lần (controller bị down), nó sẽ không tạo job cho các lần bị miss. Cấu hình `startingDeadlineSeconds` để giới hạn:
   ```yaml
   spec:
     startingDeadlineSeconds: 200  # Job phải bắt đầu trong vòng 200s
   ```

5. **Job idempotency**: Job nên được thiết kế **idempotent** — chạy nhiều lần phải cho cùng kết quả. Đặc biệt quan trọng khi có retry.

6. **Xem logs của completed pods**: Pods của Jobs hoàn thành vẫn được giữ lại (theo `successfulJobsHistoryLimit`), bạn vẫn xem được logs.

7. **Work queue pattern** thực tế: Worker pods lấy task từ Redis, RabbitMQ, hoặc SQS. Khi queue empty, worker exit 0 → Job hoàn thành.

---

## 📚 Tham khảo (References)

- [Jobs | Kubernetes Docs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [CronJob | Kubernetes Docs](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)
- [Running Automated Tasks with a CronJob](https://kubernetes.io/docs/tasks/job/automated-tasks-with-cron-jobs/)
- [Crontab Guru](https://crontab.guru/) — Test cron expressions

---

## 🔗 Next Lab

➡️ [Lab 10 — Services & Networking](../lab-10-services/README.md)
