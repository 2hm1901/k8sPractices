# 🧠 Terraform Q&A — Core Concepts

> **Cách dùng:** Đọc câu hỏi, tự trả lời trước, rồi mới mở phần đáp án.
> Mỗi câu có điểm khó: 🟢 Dễ | 🟡 Trung bình | 🔴 Khó

---

## 🏗️ PHẦN 1 — IaC & Terraform Basics

---

**Q1** 🟢 — Infrastructure as Code (IaC) là gì? Terraform giải quyết vấn đề gì so với cách provision thủ công?

<details>
<summary>💡 Đáp án</summary>

**IaC** là cách quản lý và provision infrastructure thông qua code (file cấu hình) thay vì làm thủ công trên UI/console.

**Vấn đề của provision thủ công:**
- Không reproducible — làm lại khó y hệt
- Không có version history — không biết ai thay đổi gì
- Human error — click nhầm, quên bước
- Không thể scale — tạo 100 server mất bao nhiêu công?

**Terraform giải quyết:**
- **Declarative**: Bạn mô tả *trạng thái mong muốn*, Terraform tự tính *cần làm gì*
- **Idempotent**: Chạy nhiều lần vẫn cho kết quả như nhau
- **Version control**: File `.tf` commit lên Git, track được mọi thay đổi
- **Multi-cloud**: Hỗ trợ AWS, GCP, Azure, K8s... qua cùng một tool

```
Imperative (làm thủ công):  "Tạo server → Cài nginx → Mở port 80"
Declarative (Terraform):    "Tôi muốn có: server + nginx + port 80"
                             → Terraform tự tính ra các bước cần làm
```

</details>

---

**Q2** 🟢 — Terraform workflow cơ bản gồm những lệnh nào? Mỗi lệnh làm gì?

<details>
<summary>💡 Đáp án</summary>

```bash
# 1. terraform init
# Download providers, initialize backend, setup modules
terraform init

# 2. terraform validate
# Kiểm tra cú pháp HCL có đúng không (không cần kết nối cloud)
terraform validate

# 3. terraform plan
# So sánh desired state (code) vs current state (tfstate)
# In ra những gì sẽ được CREATE/UPDATE/DESTROY — CHƯA làm gì cả
terraform plan
terraform plan -out=tfplan  # lưu plan ra file để apply sau

# 4. terraform apply
# Thực thi plan, tạo/sửa/xóa resources thật sự
terraform apply
terraform apply tfplan       # apply từ saved plan file

# 5. terraform destroy
# Xóa TẤT CẢ resources được quản lý bởi terraform trong directory này
terraform destroy
```

**Workflow chuẩn trong team:**
```
init → validate → plan (review) → apply
```

</details>

---

**Q3** 🟡 — Provider trong Terraform là gì? Khai báo provider như thế nào?

<details>
<summary>💡 Đáp án</summary>

**Provider** là plugin cho phép Terraform nói chuyện với một API/platform cụ thể (AWS, GCP, Azure, K8s, GitHub...).

Mỗi Provider định nghĩa:
- **Resources**: Những gì có thể tạo (`aws_instance`, `google_compute_instance`)
- **Data sources**: Những gì có thể đọc từ provider

**Khai báo:**
```hcl
# versions.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"    # ~> 5.0 nghĩa là >= 5.0, < 6.0
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20"
    }
  }
  required_version = ">= 1.5.0"  # Terraform CLI version
}

provider "aws" {
  region = "us-east-1"
  # Credentials: từ env vars, ~/.aws/credentials, hoặc IAM role
}
```

**`terraform init`** sẽ download provider vào `.terraform/providers/`.

</details>

---

**Q4** 🟢 — File `terraform.tfstate` là gì? Tại sao nó quan trọng?

<details>
<summary>💡 Đáp án</summary>

**`terraform.tfstate`** là file JSON lưu trữ **current state** của infrastructure — Terraform dùng nó để biết resources nào đang tồn tại trên thực tế.

**Vai trò:**
```
Code (.tf)  ←──── terraform plan ────→  tfstate (reality)
                  "cần thay đổi gì?"
```

- **Mapping**: Mỗi resource trong code được map với resource thật (VD: `aws_instance.web` → `i-0abc123def`)
- **Dependency tracking**: Biết resource nào phụ thuộc resource nào
- **Performance**: Không phải query cloud mỗi lần (dùng cached state)

**⚠️ Nguy hiểm với tfstate:**
- Chứa **sensitive values** (passwords, private keys) ở dạng plain text
- **KHÔNG commit lên Git** (thêm vào `.gitignore`)
- Nếu mất tfstate → Terraform không còn biết resources nào đang được quản lý
- Nếu nhiều người cùng chạy → **state conflict** → phải dùng Remote Backend với state locking

</details>

---

**Q5** 🟡 — Remote Backend là gì? Tại sao cần dùng trong team?

<details>
<summary>💡 Đáp án</summary>

**Remote Backend** lưu `terraform.tfstate` ở một nơi tập trung thay vì local.

**Vấn đề với local state trong team:**
- Dev A apply → state ở máy A
- Dev B không có state mới → plan sai → conflict
- Không có locking → 2 người apply cùng lúc → corrupt state

**Giải pháp — S3 Backend với DynamoDB locking (AWS):**
```hcl
terraform {
  backend "s3" {
    bucket         = "my-company-terraform-state"
    key            = "production/main.tfstate"
    region         = "us-east-1"
    # State locking: ngăn 2 người apply cùng lúc
    dynamodb_table = "terraform-state-lock"
    encrypt        = true   # Encrypt state at rest
  }
}
```

**Terraform Cloud (HashiCorp):**
```hcl
terraform {
  cloud {
    organization = "my-org"
    workspaces {
      name = "production"
    }
  }
}
```

**Lợi ích Remote Backend:**
- State được share toàn team
- **State locking**: Không ai apply được khi người khác đang apply
- **Encryption**: State được mã hóa
- **Versioning**: Rollback state khi cần

</details>

---

## 📝 PHẦN 2 — HCL Syntax & Configuration

---

**Q6** 🟢 — Sự khác nhau giữa `variable`, `local`, và `output` trong Terraform?

<details>
<summary>💡 Đáp án</summary>

| | `variable` | `local` | `output` |
|--|-----------|---------|---------|
| **Hướng** | Input (vào) | Internal | Output (ra) |
| **Ai set** | User / CI-CD | Bản thân code | Terraform in ra sau apply |
| **Thay đổi được** | Có (qua -var, tfvars) | Không (computed) | Không |
| **Dùng để** | Parameterize config | Tránh lặp code | Expose giá trị cho module khác / user |

```hcl
# Input variable — người dùng cung cấp
variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "EC2 instance type"
}

# Local — tính toán nội bộ, không cần user cung cấp
locals {
  name_prefix = "${var.environment}-${var.project}"
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Output — kết quả sau khi apply
output "instance_public_ip" {
  value       = aws_instance.web.public_ip
  description = "Public IP of the web server"
  sensitive   = false
}
```

**Cách truyền variable:**
```bash
terraform apply -var="instance_type=t3.large"   # inline
terraform apply -var-file="prod.tfvars"          # từ file
export TF_VAR_instance_type=t3.large            # env var
```

</details>

---

**Q7** 🟡 — `terraform.tfvars` và `*.auto.tfvars` khác nhau thế nào? Thứ tự ưu tiên của variable là gì?

<details>
<summary>💡 Đáp án</summary>

**Terraform tự động load:**
- `terraform.tfvars` — luôn được load nếu file tồn tại
- `*.auto.tfvars` — tất cả file kết thúc bằng `.auto.tfvars` đều được load tự động
- `terraform.tfvars.json` — tương tự nhưng dạng JSON

**Thứ tự ưu tiên (sau ghi đè trước):**
```
1. -var flag (cao nhất)           # terraform apply -var="env=prod"
2. -var-file flag                 # terraform apply -var-file="prod.tfvars"
3. *.auto.tfvars (alphabetical)
4. terraform.tfvars
5. Environment variables (TF_VAR_*)
6. Default value trong variable block (thấp nhất)
```

**Ví dụ structure:**
```
├── main.tf
├── variables.tf
├── terraform.tfvars          # default values (commit lên git)
├── prod.auto.tfvars          # prod-specific (auto-loaded)
├── secrets.tfvars            # KHÔNG commit — chứa passwords
└── .gitignore                # ignore secrets.tfvars và *.tfstate
```

</details>

---

**Q8** 🟡 — Data source khác Resource ở điểm nào? Cho ví dụ thực tế khi nào dùng data source.

<details>
<summary>💡 Đáp án</summary>

| | Resource | Data Source |
|--|---------|-------------|
| **Mục đích** | Tạo/quản lý infrastructure | Đọc thông tin đã có sẵn |
| **Terraform quản lý** | Có (lifecycle) | Không (read-only) |
| **Khai báo** | `resource "aws_vpc" "main"` | `data "aws_vpc" "existing"` |

**Data source dùng khi:**
- Cần ID của resource do team khác tạo (VPC, subnet, AMI)
- Cần tham chiếu đến resource tồn tại bên ngoài Terraform state của bạn
- Cần lookup dynamic values (latest AMI ID, AZs của region)

```hcl
# Lấy AMI mới nhất của Ubuntu (không cần hardcode ID)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-22.04-amd64-*"]
  }
}

# Lấy VPC được tạo bởi team khác (theo tag)
data "aws_vpc" "shared" {
  filter {
    name   = "tag:Name"
    values = ["shared-vpc"]
  }
}

# Dùng data source
resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id          # dynamic
  subnet_id     = data.aws_vpc.shared.id
  instance_type = var.instance_type
}
```

</details>

---

**Q9** 🟡 — Implicit dependency và explicit dependency trong Terraform là gì? Khi nào cần dùng `depends_on`?

<details>
<summary>💡 Đáp án</summary>

**Implicit dependency** — Terraform TỰ phát hiện khi một resource tham chiếu đến attribute của resource khác:

```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  # Tham chiếu vpc_id → Terraform biết subnet phụ thuộc vpc
  vpc_id     = aws_vpc.main.id   # ← implicit dependency
  cidr_block = "10.0.1.0/24"
}
```

Terraform tự động: tạo VPC trước → tạo Subnet sau.

**Explicit dependency** — Dùng `depends_on` khi dependency **không thể hiện qua attribute**:

```hcl
resource "aws_s3_bucket_policy" "main" {
  bucket = aws_s3_bucket.main.id
  policy = data.aws_iam_policy_document.main.json

  # Bucket policy cần IAM role đã tồn tại TRƯỚC,
  # nhưng không có attribute nào tham chiếu trực tiếp
  depends_on = [
    aws_iam_role.app_role
  ]
}
```

**Khi nào cần `depends_on`:**
- Resource A cần B tồn tại nhưng không dùng attribute của B
- Race condition: App cần database READY, không chỉ cần nó tồn tại
- Side effects của resource khác (VD: IAM policy propagation)

> 💡 **Tip:** Ưu tiên implicit dependency — nếu phải dùng `depends_on` nhiều, thường là sign of bad design.

</details>

---

**Q10** 🟡 — `count` và `for_each` dùng để làm gì? Chúng khác nhau thế nào?

<details>
<summary>💡 Đáp án</summary>

Cả hai dùng để tạo **nhiều instances** của cùng một resource.

**`count` — tạo theo số lượng:**
```hcl
resource "aws_instance" "server" {
  count         = 3
  instance_type = "t3.micro"
  ami           = data.aws_ami.ubuntu.id
  tags = {
    Name = "server-${count.index}"   # server-0, server-1, server-2
  }
}

# Tham chiếu: aws_instance.server[0], aws_instance.server[1]
```

**`for_each` — tạo theo map hoặc set:**
```hcl
resource "aws_iam_user" "developers" {
  for_each = toset(["alice", "bob", "charlie"])
  name     = each.key   # alice, bob, charlie
}

# Hoặc dùng map để có thêm data:
variable "servers" {
  default = {
    web = { type = "t3.micro",  az = "us-east-1a" }
    app = { type = "t3.small",  az = "us-east-1b" }
    db  = { type = "t3.medium", az = "us-east-1c" }
  }
}

resource "aws_instance" "server" {
  for_each      = var.servers
  instance_type = each.value.type
  # each.key = "web", "app", "db"
  # Tham chiếu: aws_instance.server["web"]
}
```

**Khi nào dùng cái nào:**
| | `count` | `for_each` |
|--|--------|-----------|
| **Khi nào** | Số lượng đơn giản | Resources có tên/identity riêng |
| **Vấn đề** | Xóa item giữa → re-index → destroy/recreate | Xóa item theo key → chỉ xóa item đó |
| **Tham chiếu** | `resource[0]`, `resource[1]` | `resource["name"]` |

> **Best practice:** Ưu tiên `for_each` vì ổn định hơn khi thêm/xóa items.

</details>

---

## 📦 PHẦN 3 — Modules

---

**Q11** 🟢 — Module trong Terraform là gì? Tại sao cần dùng module?

<details>
<summary>💡 Đáp án</summary>

**Module** là một nhóm Terraform resources được đóng gói lại, có thể tái sử dụng.

Mọi thư mục chứa `.tf` files đều là một module. Khi bạn chạy `terraform apply`, bạn đang dùng **root module**.

**Tại sao cần module:**
- **DRY (Don't Repeat Yourself)**: Không copy-paste config cho dev/staging/prod
- **Abstraction**: Developer dùng module `vpc` mà không cần biết bên trong làm gì
- **Standardization**: Toàn team dùng chung pattern đã được tested
- **Maintainability**: Sửa một chỗ, áp dụng cho tất cả nơi dùng

**Cấu trúc điển hình:**
```
project/
├── main.tf              ← root module (gọi các module)
├── variables.tf
├── outputs.tf
└── modules/
    ├── vpc/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── ec2/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── rds/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

</details>

---

**Q12** 🟡 — Cách gọi (call) một module và truyền variable vào module như thế nào? Lấy output của module ra thế nào?

<details>
<summary>💡 Đáp án</summary>

```hcl
# main.tf (root module)

# Gọi module local
module "vpc" {
  source = "./modules/vpc"    # path tương đối

  # Truyền variables vào module
  cidr_block   = "10.0.0.0/16"
  environment  = var.environment
  project_name = var.project_name
}

# Gọi module từ Terraform Registry
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "my-cluster"
  cluster_version = "1.29"
  vpc_id          = module.vpc.vpc_id        # ← lấy output từ module vpc
  subnet_ids      = module.vpc.private_subnets
}

# Gọi module từ Git
module "security" {
  source = "git::https://github.com/myorg/terraform-modules.git//security?ref=v1.2.0"
}
```

**Lấy output từ module:**
```hcl
# Trong modules/vpc/outputs.tf:
output "vpc_id" {
  value = aws_vpc.main.id
}

# Trong root module:
module.vpc.vpc_id    # ← cú pháp: module.<module_name>.<output_name>
```

**Sau khi thêm/sửa module, phải chạy lại:**
```bash
terraform init   # download module mới
```

</details>

---

**Q13** 🟡 — Sự khác nhau giữa module local, Terraform Registry, và Git source?

<details>
<summary>💡 Đáp án</summary>

| Source | Syntax | Khi dùng |
|--------|--------|---------|
| **Local** | `"./modules/vpc"` | Module trong cùng repo |
| **Registry** | `"hashicorp/consul/aws"` | Dùng module community đã tested |
| **Git** | `"git::https://github.com/org/repo.git//path"` | Module internal của công ty |
| **GitHub shorthand** | `"github.com/org/repo"` | Git qua HTTPS |
| **S3** | `"s3::https://s3.amazonaws.com/bucket/module.zip"` | Module trong S3 |

**Best practices:**
```hcl
# ✅ Pin version để tránh breaking changes
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.0"   # exact version, không dùng "~> 5.0" trong production
}

# ✅ Git với tag
module "internal" {
  source = "git::https://github.com/myorg/tf-modules.git//vpc?ref=v2.3.1"
  # ?ref= có thể là: tag, branch, commit hash
}
```

</details>

---

## 🔄 PHẦN 4 — State Management

---

**Q14** 🟡 — `terraform state` commands — Khi nào cần dùng và dùng thế nào?

<details>
<summary>💡 Đáp án</summary>

```bash
# Liệt kê tất cả resources trong state
terraform state list

# Xem chi tiết một resource trong state
terraform state show aws_instance.web

# Xóa resource khỏi state (KHÔNG xóa resource thật!)
# Dùng khi: muốn Terraform không quản lý resource đó nữa
terraform state rm aws_instance.old_server

# Import resource đang tồn tại vào state
# Dùng khi: resource tạo thủ công, muốn Terraform quản lý
terraform import aws_instance.web i-0abc123def456

# Di chuyển resource trong state (đổi tên)
# Dùng khi: refactor code, đổi tên resource
terraform state mv aws_instance.web aws_instance.web_server

# Pull state về local (từ remote backend)
terraform state pull > backup.tfstate

# Push state lên (NGUY HIỂM - ít khi dùng)
terraform state push backup.tfstate
```

**Trường hợp thực tế:**
- **`state rm`**: "Tôi không muốn Terraform quản lý cái DB này nữa (nhưng không xóa DB)"
- **`import`**: "Server này team tạo tay, tôi muốn đưa vào Terraform để quản lý"
- **`state mv`**: "Tôi refactor code, đổi `aws_instance.old` thành `aws_instance.new` — không muốn destroy/recreate"

</details>

---

**Q15** 🔴 — Điều gì xảy ra nếu ai đó xóa resource trực tiếp trên cloud console (ngoài Terraform)? Terraform xử lý thế nào?

<details>
<summary>💡 Đáp án</summary>

Đây là **configuration drift** — sự khác biệt giữa state (Terraform biết) và reality (cloud thực tế).

**Scenario:**
1. Terraform tạo EC2 instance → lưu vào state
2. Ai đó xóa instance trực tiếp trên AWS Console
3. State vẫn nghĩ instance tồn tại

**Khi chạy `terraform plan`:**
```
aws_instance.web: Refreshing state... [id=i-0abc123def]
╷
│ Error: Instance not found
│ i-0abc123def no longer exists
│
│ Terraform will recreate this resource
╵

Plan: 1 to add, 0 to change, 0 to destroy.
```

Terraform sẽ **tạo lại** resource vì state nói nó cần tồn tại.

**Để refresh state (cập nhật state theo thực tế):**
```bash
# Refresh state từ cloud (không apply gì cả)
terraform refresh

# Hoặc: plan đã tự refresh
terraform plan -refresh=true   # mặc định là true
```

**Nếu muốn Terraform "chấp nhận" resource bị xóa (không recreate):**
```bash
terraform state rm aws_instance.web   # xóa khỏi state
# Sau đó xóa resource block trong code
```

> **Best practice:** Không bao giờ thay đổi resource do Terraform quản lý qua console/CLI — luôn thay đổi qua code.

</details>

---

**Q16** 🟡 — `terraform.lock.hcl` là gì? Có nên commit file này lên Git không?

<details>
<summary>💡 Đáp án</summary>

**`.terraform.lock.hcl`** (dependency lock file) ghi lại chính xác version của mỗi provider được chọn, kèm checksum để verify.

```hcl
# .terraform.lock.hcl (tự sinh ra sau terraform init)
provider "registry.terraform.io/hashicorp/aws" {
  version     = "5.31.0"
  constraints = "~> 5.0"
  hashes = [
    "h1:abcdef...",    # SHA256 hash để verify integrity
  ]
}
```

**Tại sao cần:**
- `version = "~> 5.0"` trong code có thể match nhiều version (5.0, 5.1, 5.31...)
- Lock file đảm bảo mọi người trong team và CI/CD dùng **cùng version** provider
- Tránh "works on my machine" vì provider version khác nhau

**Có nên commit không?**
✅ **CÓ, nên commit** `.terraform.lock.hcl` lên Git

```bash
# Update lock file khi muốn upgrade provider
terraform init -upgrade
```

**So sánh với ecosystem khác:**
- Giống `package-lock.json` trong Node.js
- Giống `Pipfile.lock` trong Python
- Giống `go.sum` trong Go

</details>

---

## ⚡ PHẦN 5 — Functions & Expressions

---

**Q17** 🟡 — Các hàm (functions) Terraform thường dùng nhất? Cho ví dụ từng cái.

<details>
<summary>💡 Đáp án</summary>

```hcl
# --- STRING FUNCTIONS ---
# format: string formatting
name = format("server-%03d", count.index)  # → "server-001"

# join: nối list thành string
tags_str = join(",", ["web", "prod", "us-east"])  # → "web,prod,us-east"

# split: tách string thành list
parts = split(",", "web,prod")  # → ["web", "prod"]

# replace: thay thế string
safe_name = replace(var.name, " ", "-")  # "my app" → "my-app"

# lower / upper / title
env = lower(var.environment)  # "PROD" → "prod"

# --- COLLECTION FUNCTIONS ---
# length: đếm số phần tử
count = length(var.subnet_ids)

# toset: chuyển list thành set (loại bỏ duplicate)
unique_zones = toset(["us-east-1a", "us-east-1b", "us-east-1a"])

# tolist, tomap: chuyển đổi type

# merge: gộp 2 maps (key trùng → sau ghi đè trước)
all_tags = merge(local.common_tags, var.extra_tags)

# flatten: làm phẳng list lồng nhau
# flatten([["a","b"], ["c"]]) → ["a","b","c"]

# --- ENCODING ---
# jsonencode / jsondecode
policy = jsonencode({
  Version = "2012-10-17"
  Statement = [...]
})

# base64encode / base64decode
encoded = base64encode("secret-password")

# --- FILESYSTEM ---
# file: đọc nội dung file
user_data = file("${path.module}/scripts/startup.sh")

# templatefile: đọc file và render template
rendered = templatefile("${path.module}/templates/config.tpl", {
  db_host = var.db_host
  app_port = var.app_port
})

# --- NUMERIC ---
max(var.min_size, 1)
min(var.max_size, 100)
ceil(2.3)   # → 3
floor(2.9)  # → 2
```

</details>

---

**Q18** 🟡 — `for` expression trong Terraform dùng để làm gì? Cho ví dụ thực tế.

<details>
<summary>💡 Đáp án</summary>

**`for` expression** dùng để transform list hoặc map sang dạng khác.

```hcl
# Transform list → list
variable "names" {
  default = ["alice", "bob", "charlie"]
}

# Uppercase tất cả
upper_names = [for name in var.names : upper(name)]
# → ["ALICE", "BOB", "CHARLIE"]

# Filter (chỉ lấy những cái thỏa điều kiện)
long_names = [for name in var.names : name if length(name) > 3]
# → ["alice", "charlie"]

# Transform list → map
name_lengths = {for name in var.names : name => length(name)}
# → {"alice" = 5, "bob" = 3, "charlie" = 7}

# Transform map → map
variable "servers" {
  default = {
    web = "t3.micro"
    app = "t3.small"
  }
}

# Thêm prefix vào tất cả keys
prefixed = {for k, v in var.servers : "prod-${k}" => v}
# → {"prod-web" = "t3.micro", "prod-app" = "t3.small"}
```

**Ứng dụng thực tế:**
```hcl
# Tạo map từ list để dùng với for_each
resource "aws_subnet" "private" {
  for_each = {
    for idx, az in var.availability_zones :
    az => {
      cidr = cidrsubnet(var.vpc_cidr, 8, idx)
      az   = az
    }
  }
  availability_zone = each.value.az
  cidr_block        = each.value.cidr
}
```

</details>

---

**Q19** 🟡 — `dynamic` block dùng để làm gì? Cho ví dụ.

<details>
<summary>💡 Đáp án</summary>

**`dynamic` block** dùng để tạo **nested blocks lặp lại** trong resource dựa trên biến.

**Vấn đề không có dynamic:**
```hcl
# Phải hardcode từng security group rule
resource "aws_security_group" "web" {
  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
  }
  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
  }
  # → không linh hoạt!
}
```

**Với dynamic block:**
```hcl
variable "ingress_rules" {
  default = [
    { port = 80,  protocol = "tcp" },
    { port = 443, protocol = "tcp" },
    { port = 8080, protocol = "tcp" },
  ]
}

resource "aws_security_group" "web" {
  name = "web-sg"

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = ingress.value.protocol
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
}
```

> Dùng `dynamic` khi số lượng nested blocks không biết trước (dynamic từ variable).

</details>

---

## 🔴 PHẦN 6 — Câu hỏi tình huống thực tế

---

**Q20** 🟡 — **Tình huống:** `terraform plan` hiển thị resource sẽ bị **destroy** và **recreate** (thay vì chỉ update in-place). Điều này nghĩa là gì và khi nào xảy ra?

<details>
<summary>💡 Đáp án</summary>

Khi output là:
```
-/+ aws_instance.web (must be replaced)
  ~ instance_type = "t3.micro" → "t3.small"  # update in-place ✅
  -/+ ami          = "ami-old" → "ami-new"    # forces replacement ❌
```

**Ký hiệu:**
- `+` : Create
- `-` : Destroy
- `~` : Update in-place
- `-/+` : Destroy then Create (replace)

**Khi nào resource bị replace (destroy + create):**
- Thay đổi attribute mà cloud provider không hỗ trợ update in-place (VD: AMI của EC2, AZ của RDS)
- Attribute được đánh dấu `ForceNew: true` trong provider

**⚠️ Nguy hiểm:** Replace có nghĩa là **downtime** (nếu không có HA) và **mất data** (nếu không có backup).

**Giải pháp:**
```hcl
# Lifecycle rules để kiểm soát behavior
resource "aws_instance" "web" {
  lifecycle {
    # Tạo mới TRƯỚC rồi mới xóa cũ (zero downtime replace)
    create_before_destroy = true

    # Ngăn Terraform xóa resource này (protect production!)
    prevent_destroy = true

    # Ignore changes đến ami (không trigger replace khi ami thay đổi)
    ignore_changes = [ami, tags]
  }
}
```

</details>

---

**Q21** 🟡 — **Tình huống:** Chạy `terraform apply` bị lỗi ở giữa chừng. State hiện tại như thế nào và bạn xử lý thế nào?

<details>
<summary>💡 Đáp án</summary>

**State sau lỗi giữa chừng:**
- Những resource đã tạo thành công → **ĐÃ được lưu vào state**
- Những resource chưa tạo được → **chưa có trong state**
- Terraform KHÔNG rollback tự động (không phải transaction)

```
Plan: 5 to add
Apply:
  ✅ aws_vpc.main     → created (trong state)
  ✅ aws_subnet.pub   → created (trong state)
  ❌ aws_instance.web → FAILED (timeout)
  ⏭️ aws_elb.main     → skipped (chưa chạy đến)
  ⏭️ aws_dns.record   → skipped
```

**Xử lý:**
```bash
# Bước 1: Đọc error message cẩn thận để hiểu nguyên nhân
# Bước 2: Fix nguyên nhân (permissions, quota, network...)
# Bước 3: Chạy lại apply — Terraform chỉ tạo những gì còn thiếu
terraform apply   # ← idempotent, an toàn để retry

# Bước 4: Nếu state bị corrupt (hiếm gặp):
terraform refresh  # sync state với reality trước
terraform apply
```

**State locking:**
```bash
# Nếu apply bị interrupt nhưng lock chưa release:
terraform force-unlock <lock-id>
# Lock ID thấy trong error message
```

> **Key insight:** `terraform apply` **idempotent** — chạy lại an toàn, chỉ tạo những gì thiếu.

</details>

---

**Q22** 🔴 — **Tình huống:** Bạn cần đổi tên một resource trong code (từ `aws_instance.old` thành `aws_instance.new`) mà KHÔNG muốn Terraform destroy và recreate. Làm thế nào?

<details>
<summary>💡 Đáp án</summary>

**Nếu chỉ đổi tên trong code và `terraform plan`:**
```
Plan: 1 to add, 0 to change, 1 to destroy.
# → Terraform nghĩ "old" bị xóa, "new" được tạo mới — SAI!
```

**Giải pháp 1: `terraform state mv` (cách cũ, vẫn dùng được)**
```bash
# Bước 1: Di chuyển trong state trước
terraform state mv aws_instance.old aws_instance.new

# Bước 2: Đổi tên trong code
# Bước 3: Plan để verify — phải thấy 0 changes
terraform plan  # → No changes. Infrastructure is up-to-date.
```

**Giải pháp 2: `moved` block (Terraform 1.1+, cách mới, preferred)**
```hcl
# Thêm moved block vào code
moved {
  from = aws_instance.old
  to   = aws_instance.new
}

# Sau đó đổi tên resource trong code
resource "aws_instance" "new" {   # ← đổi từ "old" sang "new"
  # ... unchanged config
}
```

```bash
terraform plan
# → Plan: 0 to add, 0 to change, 0 to destroy.
# "moved" block xử lý rename trong state tự động khi apply

terraform apply
# Sau apply xong, xóa moved block khỏi code
```

> **Ưu điểm `moved` block:** Tự document "resource này được rename từ đâu", không cần chạy state command thủ công.

</details>

---

**Q23** 🔴 — **Tình huống:** Team bạn có 3 môi trường: dev, staging, prod với cùng infrastructure nhưng config khác nhau (size, count). Tổ chức code Terraform như thế nào?

<details>
<summary>💡 Đáp án</summary>

**Có 3 approach phổ biến:**

---

**Approach 1: Thư mục riêng cho mỗi môi trường (Recommended)**
```
terraform/
├── modules/
│   ├── vpc/
│   ├── ec2/
│   └── rds/
├── environments/
│   ├── dev/
│   │   ├── main.tf        # gọi modules
│   │   ├── variables.tf
│   │   └── terraform.tfvars  # dev-specific values
│   ├── staging/
│   │   ├── main.tf
│   │   └── terraform.tfvars
│   └── prod/
│       ├── main.tf
│       └── terraform.tfvars
```

Mỗi môi trường có **state riêng** → an toàn, cô lập.

---

**Approach 2: Terraform Workspace**
```bash
terraform workspace new dev
terraform workspace new staging
terraform workspace new prod

terraform workspace select prod
terraform apply -var-file="prod.tfvars"
```

```hcl
# Trong code dùng workspace name
resource "aws_instance" "web" {
  count = terraform.workspace == "prod" ? 3 : 1
}
```

⚠️ Vấn đề: Tất cả workspaces share cùng backend config, khó audit riêng.

---

**Approach 3: Terragrunt (wrapper)**
- DRY hơn: không copy-paste `main.tf`
- Mỗi môi trường chỉ có `terragrunt.hcl` với values
- Tự động manage state per-env

---

**Recommendation:**
- Nhỏ/đơn giản: **Workspace**
- Team/Production: **Thư mục riêng** (approach 1)
- Complex/nhiều team: **Terragrunt**

</details>

---

**Q24** 🔴 — **Tình huống:** `terraform plan` ra "No changes. Infrastructure is up-to-date." nhưng bạn biết thực tế có resource bị thay đổi tay. Tại sao và xử lý thế nào?

<details>
<summary>💡 Đáp án</summary>

**Nguyên nhân:**

**1. `ignore_changes` trong lifecycle:**
```hcl
lifecycle {
  ignore_changes = [tags, user_data]  # Terraform bỏ qua thay đổi của fields này
}
```

**2. Resource bị thay đổi nhưng Terraform không track attribute đó:**
Một số attributes không được refresh từ API (provider limitation).

**3. State chưa được refresh:**
```bash
# Force refresh state từ cloud
terraform refresh

# Hoặc plan với refresh
terraform plan -refresh=true
```

**4. Drift không được detect vì chưa đủ permissions để đọc:**
Terraform cần quyền READ để detect drift.

**Cách detect drift:**

```bash
# Refresh và xem differences
terraform plan -refresh=true -detailed-exitcode
# Exit code 0: no changes
# Exit code 1: error
# Exit code 2: changes detected

# Xem state thực tế
terraform show
terraform state show aws_instance.web
```

**Phòng tránh drift:**
- Dùng **OPA/Sentinel** để block thay đổi ngoài Terraform
- Chạy `terraform plan` định kỳ trong CI (drift detection)
- Terraform Cloud có tính năng Drift Detection tự động

</details>

---

**Q25** 🟡 — Sự khác nhau giữa `terraform destroy` và `terraform apply -destroy`? Khi nào dùng cái nào?

<details>
<summary>💡 Đáp án</summary>

```bash
# Hai lệnh này tương đương nhau về chức năng
terraform destroy
terraform apply -destroy

# Cả hai đều:
# 1. Tạo destroy plan (xóa TẤT CẢ resources trong state)
# 2. Hỏi confirm (yes/no)
# 3. Xóa resources theo thứ tự ngược (dependency aware)
```

**Sự khác biệt nhỏ:**
```bash
# Lưu destroy plan ra file (chỉ với apply -destroy)
terraform plan -destroy -out=destroy.tfplan
terraform apply destroy.tfplan  # áp dụng plan đã lưu — không hỏi confirm nữa

# Xóa resource cụ thể (không phải tất cả)
terraform destroy -target=aws_instance.web
terraform apply -destroy -target=aws_instance.web
```

**Khi cần xóa từng phần:**
```bash
# Chỉ xóa một module
terraform destroy -target=module.old_service

# Chỉ xóa một resource
terraform destroy -target=aws_s3_bucket.temp_data
```

> ⚠️ `-target` là workaround, không phải best practice. Dùng khi cần thiết, không lạm dụng.

</details>

---

## 🎯 Bảng tự chấm điểm

| Phần | Câu | Trả lời đúng |
|------|-----|-------------|
| IaC & Basics | Q1–Q5 | /5 |
| HCL Syntax | Q6–Q10 | /5 |
| Modules | Q11–Q13 | /3 |
| State Management | Q14–Q16 | /3 |
| Functions & Expressions | Q17–Q19 | /3 |
| Tình huống thực tế | Q20–Q25 | /6 |
| **TỔNG** | | **/25** |

### Đánh giá

| Điểm | Mức độ |
|------|--------|
| 21–25 | 🏆 Excellent — Nắm vững Terraform core, sẵn sàng học Advanced (Terragrunt, Sentinel, CDK) |
| 16–20 | ✅ Good — Hiểu cơ bản tốt, cần thực hành thêm state management và modules |
| 11–15 | 📖 Fair — Cần ôn lại workflow và HCL syntax, thực hành deploy real infrastructure |
| < 11 | 🔄 Needs work — Bắt đầu từ đầu với `terraform init/plan/apply` trên môi trường local |

---

## 📚 Chủ đề học tiếp (Advanced)

Khi đã nắm core, tiếp theo học:
- **Terragrunt** — DRY wrapper cho Terraform
- **Terraform Cloud / Enterprise** — Remote runs, policy as code
- **Sentinel** — Policy as Code (OPA alternative)
- **CDK for Terraform (CDKTF)** — Viết Terraform bằng Python/TypeScript
- **Testing**: `terratest` (Go), `terraform test` (native)
- **Security**: `tfsec`, `checkov`, `terrascan`

---

> 💡 **Tip học hiệu quả:** Deploy thật một cái gì đó lên AWS/GCP free tier — EC2 + Security Group + S3 — rồi thực hành destroy và re-apply để thấy idempotency hoạt động!
