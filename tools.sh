#!/bin/bash
set -e

echo "====================================================="
echo " Starting Tools Installation"
echo "====================================================="

# ── Variables ──────────────────────────────────────────
AWS_REGION="${AWS_REGION:-ap-south-1}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-my-eks-cluster}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.medium}"
ECR_URL="${ECR_URL:-}"

# ── System Update ──────────────────────────────────────
echo "[1/12] System update..."
sudo apt update -y
sudo chmod 755 /home/ubuntu

# ── Docker ─────────────────────────────────────────────
echo "[2/12] Installing Docker..."
sudo apt install docker.io -y
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker ubuntu
sudo usermod -aG docker jenkins || true

# ── SonarQube ──────────────────────────────────────────
echo "[3/12] Starting SonarQube..."
sudo docker pull sonarqube:latest
sudo docker run -dit \
  --name sonarqube \
  --restart always \
  -p 9000:9000 \
  sonarqube:latest

# ── AWS CLI ────────────────────────────────────────────
echo "[4/12] Installing AWS CLI..."
sudo apt install python3 python3-pip unzip wget gnupg -y
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install
rm -rf awscliv2.zip aws/
aws configure set default.region "$AWS_REGION"
aws configure set default.output json
aws --version

# ── ECR Login ──────────────────────────────────────────
if [ -n "$ECR_URL" ]; then
  echo "[4b] Logging into ECR..."
  aws ecr get-login-password --region "$AWS_REGION" \
    | docker login --username AWS --password-stdin "$ECR_URL"
fi

# ── Java 17 ────────────────────────────────────────────
echo "[5/12] Installing Java 17..."
sudo apt install openjdk-17-jdk -y
java --version

# ── Maven ──────────────────────────────────────────────
echo "[6/12] Installing Maven..."
sudo apt install maven -y
mvn --version

# ── Git ────────────────────────────────────────────────
echo "[6b] Installing Git..."
sudo apt install git -y
git --version

# ── Trivy ──────────────────────────────────────────────
echo "[7/12] Installing Trivy..."
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key \
  | sudo gpg --dearmor \
  | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
  | sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt update -y && sudo apt install trivy -y
trivy --version

# ── Helm ───────────────────────────────────────────────
echo "[8/12] Installing Helm..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version

# ── Jenkins ────────────────────────────────────────────
echo "[9/12] Installing Jenkins..."
sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update -y && sudo apt install jenkins -y
sudo systemctl start jenkins
sudo systemctl enable jenkins
sudo usermod -aG docker jenkins || true

# ── kubectl ────────────────────────────────────────────
echo "[10/12] Installing kubectl..."
curl -LO "https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client

# ── eksctl ─────────────────────────────────────────────
echo "[11/12] Installing eksctl..."
curl --silent --location --retry 3 \
  "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_linux_amd64.tar.gz" \
  -o eksctl.tar.gz
tar -xzf eksctl.tar.gz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
rm -f eksctl.tar.gz
eksctl version

# ── EKS kubeconfig (cluster created by Terraform) ──────
echo "[12/12] Updating kubeconfig for EKS cluster..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME"

# ── kubeconfig for ubuntu + jenkins ────────────────────
sudo mkdir -p /home/ubuntu/.kube
sudo cp ~/.kube/config /home/ubuntu/.kube/config
sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube

sudo mkdir -p /var/lib/jenkins/.kube
sudo cp /home/ubuntu/.kube/config /var/lib/jenkins/.kube/config || true
sudo chown -R jenkins:jenkins /var/lib/jenkins/.kube || true

# ── Prometheus & Grafana ───────────────────────────────
echo "[+] Installing Prometheus & Grafana via Helm..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

kubectl create namespace monitoring || true

helm install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword='admin@Grafana123' \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set grafana.service.type=LoadBalancer \
  --set prometheus.service.type=LoadBalancer \
  --set alertmanager.service.type=LoadBalancer \
  --wait --timeout 10m

helm install node-exporter \
  prometheus-community/prometheus-node-exporter \
  --namespace monitoring \
  --set service.type=ClusterIP

kubectl apply -f https://raw.githubusercontent.com/prometheus/jmx_exporter/main/example_configs/jenkins.yaml \
  -n monitoring || true

# ── Verify deployments ─────────────────────────────────
kubectl get pods -n monitoring
kubectl get svc -n monitoring

# ── Save monitoring URLs ───────────────────────────────
GRAFANA_URL=$(kubectl get svc kube-prometheus-stack-grafana \
  -n monitoring \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo 'pending')

PROMETHEUS_URL=$(kubectl get svc kube-prometheus-stack-prometheus \
  -n monitoring \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo 'pending')

echo "Grafana:    http://$GRAFANA_URL"      > /tmp/monitoring_urls.txt
echo "Prometheus: http://$PROMETHEUS_URL:9090" >> /tmp/monitoring_urls.txt
cat /tmp/monitoring_urls.txt

# ── Final log ──────────────────────────────────────────
echo "====================================================="
echo " Installation Complete"
echo "====================================================="
{
  echo "=== Setup Complete ==="
  date
  docker --version
  java --version
  mvn --version
  aws --version
  kubectl version --client
  eksctl version
  helm version
  trivy --version
  cat /tmp/monitoring_urls.txt
} > /tmp/installation.log 2>&1

cat /tmp/installation.log
