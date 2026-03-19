# CloudShield DevSecOps — CI/CD Pipeline

## 🏗️ Architecture

```
GitHub Actions
  ├── 🔐 Security Scan     (Checkov + tfsec)
  ├── 📋 Terraform Plan
  ├── 🚀 Terraform Apply   (main branch only)
  ├── 🐳 Docker Build      (Maven + ECR push + Trivy scan)
  ├── 🚢 Deploy to EKS     (Boardgame app + public URL)
  └── 💣 Terraform Destroy (manual only)
            │
            ▼
AWS ap-south-1
  ├── VPC (10.0.0.0/16)
  │     ├── Subnet A (10.0.1.0/24) — ap-south-1a
  │     └── Subnet B (10.0.2.0/24) — ap-south-1b
  ├── ECR Repository       (balu-elastic-ecr)
  ├── EC2 Instance         (tools: Docker, SonarQube, AWS CLI)
  │     └── EBS Volume     (gp3, encrypted)
  └── EKS Cluster          (balu-cluster22, v1.29)
        ├── boardgame namespace
        │     └── Boardgame App (LoadBalancer → port 80)
        └── monitoring namespace
              ├── Prometheus   (LoadBalancer)
              ├── Grafana      (LoadBalancer)
              └── Node Exporter
```

---

## 🚀 Pipeline Flow

```
git push → main
    │
    ├─ 1. 🔐 Security Scan   — Checkov + tfsec on Terraform code
    ├─ 2. 📋 Terraform Plan  — preview infrastructure changes
    ├─ 3. 🚀 Terraform Apply — create VPC, EKS, EC2, ECR
    ├─ 4. 🐳 Docker Build    — build boardgame JAR, scan, push to ECR
    ├─ 5. 🚢 Deploy to EKS   — deploy image, print public URL
    └─ 6. 💣 Destroy         — manual trigger only
```

### Manual triggers (workflow_dispatch)
- **plan** — dry run only
- **apply** — full deploy
- **destroy** — deletes all AWS resources

---

## 📁 File Structure

```
.
├── .github/
│   └── workflows/
│       ├── terraform-cicd.yml    # Main pipeline
│       └── monitoring.yml        # Prometheus + Grafana deploy
├── k8s/
│   └── k8s-boardgame.yml         # Boardgame K8s deployment + service
├── monitoring/
│   ├── prometheus-rules.yaml     # Alert rules
│   └── grafana-dashboard.yaml    # Dashboards + datasource
├── main.tf                       # VPC, EC2, ECR, EBS, IAM
├── eks.tf                        # EKS cluster + node group + security groups
├── provisioners.tf               # EC2 null_resource provisioners
├── outputs.tf                    # EC2 IP, ECR URL, EKS outputs
├── variables.tf                  # All input variables
├── versions.tf                   # Provider versions + S3 backend
├── tools.sh                      # EC2 installation script
├── Dockerfile                    # Multi-stage build (Maven → JRE)
├── app.js                        # Node.js health check app
└── package.json                  # Node.js dependencies
```

---

## 🔑 GitHub Secrets Required

Go to **Settings → Secrets and variables → Actions** and add:

| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key |
| `TF_STATE_BUCKET` | S3 bucket for Terraform state |
| `TF_LOCK_TABLE` | DynamoDB table for state locking |
| `KEY_PAIR_NAME` | EC2 key pair name |
| `EC2_PRIVATE_KEY` | Contents of `.pem` private key |
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin password |

---

## 🪣 S3 Backend Setup (one-time)

```bash
# Create S3 bucket
aws s3api create-bucket \
  --bucket your-tf-state-bucket \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket your-tf-state-bucket \
  --versioning-configuration Status=Enabled

# Create DynamoDB table
aws dynamodb create-table \
  --table-name your-tf-lock-table \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-south-1
```

---

## 🐳 Docker Image

The Boardgame app is a **Java Spring Boot** application built using Maven:

```
Stage 1 — Builder
  Maven 3.9.6 + Eclipse Temurin 11
  Clones boardgame repo
  Runs: mvn clean package -DskipTests

Stage 2 — Production
  Eclipse Temurin 11 JRE (slim)
  Copies JAR → app.jar
  EXPOSE 8080
  ENTRYPOINT java -jar app.jar
```

Images are tagged as:
- `boardgame-v<date>-<sha>` — versioned
- `boardgame-latest` — always latest

---

## ☸️ Kubernetes

```yaml
Namespace:  boardgame
Deployment: boardgame-app (2 replicas)
Service:    boardgame-svc (LoadBalancer, port 80 → 8080)
HPA:        min 2, max 5 pods (70% CPU)
```

---

## 📊 Monitoring

Deploy monitoring stack:
```
GitHub → Actions → Deploy Monitoring Stack → Run workflow
```

Get URLs after deployment:
```bash
# Grafana
kubectl get svc kube-prometheus-stack-grafana -n monitoring

# Prometheus
kubectl get svc kube-prometheus-stack-prometheus -n monitoring
```

**Grafana login:** `admin` / your `GRAFANA_ADMIN_PASSWORD`

| Dashboard | Grafana ID |
|---|---|
| Kubernetes Cluster | 6417 |
| Node Exporter Full | 1860 |
| EKS Cluster | 17119 |

---

## 🌐 Access Application

After pipeline completes, the public URL appears in:
```
GitHub → Actions → your run → Summary tab
```

Or run manually:
```bash
kubectl get svc boardgame-svc -n boardgame
```

---

## 💣 Destroy All Resources

```
GitHub → Actions → Terraform CI/CD Pipeline
  → Run workflow → select "destroy" → Run
```

This automatically:
1. Deletes K8s LoadBalancer services
2. Deletes EKS node group + cluster
3. Deletes Classic Load Balancers
4. Deletes orphaned security groups
5. Releases Elastic IPs
6. Deletes ECR images
7. Runs `terraform destroy`

---

## 🔐 Security Tools

| Tool | Purpose |
|---|---|
| Checkov | Terraform IaC security scanning |
| tfsec | Terraform security analysis |
| Trivy | Docker image vulnerability scanning |
| Helmet.js | HTTP security headers |
| IMDSv2 | EC2 metadata service hardening |
| EBS encryption | Storage encryption at rest |
