# Jenkins EKS Infrastructure — CI/CD + Monitoring

## 🏗️ Architecture

```
GitHub Actions
  ├── Security Scan (Checkov + tfsec)
  ├── Terraform Plan  ──► PR comment
  ├── Terraform Apply ──► main branch only (requires approval)
  └── Deploy Monitoring (auto-triggered after Apply)
            │
            ▼
AWS ap-south-1
  ├── VPC + Subnet + IGW
  ├── EC2 (Jenkins + SonarQube + Trivy)
  │     └── EBS 100GB (gp3)
  ├── ECR Repository
  └── EKS Cluster (balu-cluster22)
        └── monitoring namespace
              ├── Prometheus (LoadBalancer)
              ├── Grafana    (LoadBalancer)
              ├── Alertmanager
              └── Node Exporter (DaemonSet)
```

---

## ⚠️ SECURITY: Remove Hardcoded Credentials

Your original `main.tf` contained hardcoded AWS keys. **Rotate those keys immediately** in the AWS IAM console, then use the new `variables.tf` approach.

---

## 🔑 GitHub Secrets to Configure

Go to **Settings → Secrets and variables → Actions** in your repo and add:

| Secret Name | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | Your AWS access key |
| `AWS_SECRET_ACCESS_KEY` | Your AWS secret key |
| `TF_STATE_BUCKET` | S3 bucket name for Terraform state |
| `TF_LOCK_TABLE` | DynamoDB table name for state locking |
| `KEY_PAIR_NAME` | EC2 Key Pair name (e.g. `balu-task-key`) |
| `EC2_PRIVATE_KEY` | Full contents of your `.pem` private key |
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin password |
| `SLACK_WEBHOOK_URL` | (Optional) Slack webhook for notifications |

---

## 🪣 S3 Backend Setup (one-time)

```bash
# Create S3 bucket for Terraform state
aws s3api create-bucket \
  --bucket your-tf-state-bucket \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket your-tf-state-bucket \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name your-tf-lock-table \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-south-1
```

---

## 📁 File Structure

```
.
├── .github/
│   └── workflows/
│       ├── terraform.yml      # Main CI/CD pipeline
│       └── monitoring.yml     # Prometheus + Grafana deploy
├── monitoring/
│   ├── prometheus-rules.yaml  # Alert rules (Jenkins + EKS)
│   └── grafana-dashboard.yaml # Pre-built dashboards + datasource
├── main.tf                    # Core infrastructure (no hardcoded creds)
├── variables.tf               # All input variables
├── outputs.tf                 # Useful outputs (URLs, IPs)
└── versions.tf                # Provider versions + S3 backend
```

---

## 🚀 Pipeline Flow

```
git push → main
    │
    ├─ 1. security-scan   (Checkov + tfsec)
    ├─ 2. terraform-plan  (always runs, posts to PR)
    ├─ 3. terraform-apply (main branch + manual approval)
    └─ 4. deploy-monitoring (auto after apply succeeds)
```

### Manual triggers (workflow_dispatch)
- **Plan** — dry run only
- **Apply** — deploy infrastructure
- **Destroy** — requires `destroy-approval` environment approval

---

## 📊 Monitoring Access

After deployment, get your URLs:

```bash
# Grafana
kubectl get svc kube-prometheus-stack-grafana -n monitoring

# Prometheus
kubectl get svc kube-prometheus-stack-prometheus -n monitoring

# Alertmanager
kubectl get svc kube-prometheus-stack-alertmanager -n monitoring
```

**Grafana login:** `admin` / your `GRAFANA_ADMIN_PASSWORD` secret

### Pre-configured dashboards (import by ID in Grafana)
| Dashboard | Grafana ID |
|---|---|
| Kubernetes Cluster | 6417 |
| Node Exporter Full | 1860 |
| Jenkins Performance | 9964 |
| EKS Cluster | 17119 |

---

## 🔔 Alerts Configured

| Alert | Trigger | Severity |
|---|---|---|
| JenkinsDown | Jenkins unreachable 5m | Critical |
| JenkinsHighJobFailureRate | >50% builds failing | Warning |
| JenkinsQueueLengthHigh | Queue > 10 for 10m | Warning |
| NodeHighCPU | CPU > 85% for 10m | Warning |
| NodeHighMemory | Memory > 85% for 10m | Warning |
| NodeDiskPressure | Disk < 15% free | Critical |
| PodCrashLooping | >5 restarts in 15m | Critical |