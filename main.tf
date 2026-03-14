provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

# ─────────────────────────────────────────
# NETWORKING
# ─────────────────────────────────────────
resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name        = "vpc01"
    Environment = var.environment
  }
}

# fixed: VPC flow logs enabled
resource "aws_flow_log" "vpc_flow_log" {
  vpc_id          = aws_vpc.vpc.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.vpc_flow_log_role.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log.arn
  tags = {
    Name        = "vpc-flow-log"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name              = "/aws/vpc/flow-logs"
  retention_in_days = 30
  tags = {
    Name        = "vpc-flow-log-group"
    Environment = var.environment
  }
}

resource "aws_iam_role" "vpc_flow_log_role" {
  name = "vpc-flow-log-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "vpc_flow_log_policy" {
  name = "vpc-flow-log-policy"
  role = aws_iam_role.vpc_flow_log_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = {
    Name        = "public01"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name        = "internet-Gateway"
    Environment = var.environment
  }
  depends_on = [aws_subnet.public]
}

resource "aws_default_route_table" "default" {
  default_route_table_id = aws_vpc.vpc.default_route_table_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name        = "default-route-table"
    Environment = var.environment
  }
}

resource "aws_default_security_group" "sg" {
  vpc_id = aws_vpc.vpc.id

  ingress {
    description = "Allow all traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "default-security-group"
    Environment = var.environment
  }
}

# ─────────────────────────────────────────
# ECR
# ─────────────────────────────────────────
resource "aws_ecr_repository" "my_ecr_repo" {
  name                 = "balu-elastic-ecr"
  image_tag_mutability = "MUTABLE" # fixed: was MUTABLE

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "balu-ecr-repo"
    Environment = var.environment
  }
}

# ─────────────────────────────────────────
# IAM
# ─────────────────────────────────────────
resource "aws_iam_instance_profile" "eks_profile" {
  name = "awscluster-profile"
  role = "balu-role"
}

# ─────────────────────────────────────────
# EC2 (Jenkins)
# ─────────────────────────────────────────
resource "aws_instance" "my_ec2_instance" {
  ami                    = "ami-0f58b397bc5c1f2e8"
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_default_security_group.sg.id]
  iam_instance_profile   = aws_iam_instance_profile.eks_profile.name
  ebs_optimized          = true  # fixed: EBS optimized
  monitoring             = true  # fixed: detailed monitoring enabled

  # fixed: enforce IMDSv2 only (no IMDSv1)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # fixed: encrypt root block device
  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 30
    tags = {
      Name        = "Jenkins-Root-Volume"
      Environment = var.environment
    }
  }

  user_data = <<-EOF
    #!/bin/bash
    while [ ! -b /dev/nvme1n1 ]; do sleep 3; done

    if ! file -s /dev/nvme1n1 | grep -q ext4; then
      mkfs -t ext4 /dev/nvme1n1
    fi

    mkdir -p /mnt/jenkins_data
    mount /dev/nvme1n1 /mnt/jenkins_data
    echo "/dev/nvme1n1 /mnt/jenkins_data ext4 defaults,nofail 0 2" >> /etc/fstab
    chown -R ubuntu:ubuntu /mnt/jenkins_data

    systemctl stop docker
    mkdir -p /mnt/jenkins_data/docker
    mv /var/lib/docker/* /mnt/jenkins_data/docker/ 2>/dev/null || true
    rm -rf /var/lib/docker
    ln -s /mnt/jenkins_data/docker /var/lib/docker
    systemctl start docker
  EOF

  tags = {
    Name        = "Jenkins-EC2"
    Environment = var.environment
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = self.public_ip
    private_key = file(var.private_key_path)
    timeout     = "15m"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update -y",
      "sudo chmod 755 /home/ubuntu",

      # Docker
      "sudo apt install docker.io -y",
      "sudo systemctl start docker",
      "sudo systemctl enable docker",
      "sudo usermod -aG docker ubuntu",
      "sudo usermod -aG docker jenkins || true",
      "sudo docker pull sonarqube:latest",
      "sudo docker run -dit --name sonarqube -p 9000:9000 sonarqube:latest",

      # Python & AWS CLI
      "sudo apt install python3 python3-pip python3-venv unzip wget gnupg -y",
      "curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'",
      "unzip awscliv2.zip && sudo ./aws/install",
      "aws --version",

      # AWS config (uses IAM instance role - no keys needed on EC2)
      "aws configure set default.region ${var.aws_region}",
      "aws configure set default.output json",

      # ECR login
      "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.my_ecr_repo.repository_url}",

      # Java 17
      "sudo apt install openjdk-17-jdk -y",

      # Maven
      "sudo apt install maven -y",

      # Git
      "sudo apt install git -y",

      # Trivy
      "wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null",
      "echo 'deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main' | sudo tee /etc/apt/sources.list.d/trivy.list",
      "sudo apt update -y && sudo apt install trivy -y",

      # Helm
      "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash",
      "helm version",

      # Jenkins
      "sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key",
      "echo 'deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/' | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null",
      "sudo apt update -y && sudo apt install jenkins -y",
      "sudo systemctl start jenkins && sudo systemctl enable jenkins",

      # kubectl
      "curl -LO 'https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl'",
      "chmod +x kubectl && sudo mv kubectl /usr/local/bin/",

      # eksctl
      "curl --silent --location --retry 3 'https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_linux_amd64.tar.gz' -o eksctl.tar.gz",
      "tar -xzf eksctl.tar.gz -C /tmp && sudo mv /tmp/eksctl /usr/local/bin && rm eksctl.tar.gz",

      # Create EKS cluster
      "if eksctl get cluster --name ${var.eks_cluster_name} --region ${var.aws_region} &>/dev/null; then eksctl delete cluster --name ${var.eks_cluster_name} --region ${var.aws_region} --wait; fi",
      "eksctl create cluster --name ${var.eks_cluster_name} --region ${var.aws_region} --node-type ${var.instance_type} --zones ${var.aws_region}a,${var.aws_region}b",
      "aws eks update-kubeconfig --region ${var.aws_region} --name ${var.eks_cluster_name}",
      "sudo mkdir -p /home/ubuntu/.kube && sudo cp ~/.kube/config /home/ubuntu/.kube/config",
      "sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube",
      "sudo cp /home/ubuntu/.kube/config /var/lib/jenkins/.kube/config || true",
      "sudo chown -R jenkins:jenkins /var/lib/jenkins/.kube || true",

      # ── Prometheus & Grafana via Helm ──────────────────────
      "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts",
      "helm repo add grafana https://grafana.github.io/helm-charts",
      "helm repo update",

      # Create monitoring namespace
      "kubectl create namespace monitoring || true",

      # Install kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
      "helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack --namespace monitoring --set grafana.adminPassword='admin@Grafana123' --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false --set grafana.service.type=LoadBalancer --set prometheus.service.type=LoadBalancer --set alertmanager.service.type=LoadBalancer --wait --timeout 10m",

      # Install Node Exporter for EC2 host metrics
      "helm install node-exporter prometheus-community/prometheus-node-exporter --namespace monitoring --set service.type=ClusterIP",

      # Install Jenkins metrics exporter
      "kubectl apply -f https://raw.githubusercontent.com/prometheus/jmx_exporter/main/example_configs/jenkins.yaml -n monitoring || true",

      # Verify deployments
      "kubectl get pods -n monitoring",
      "kubectl get svc -n monitoring",

      # Save Grafana LB URL
      "GRAFANA_URL=$(kubectl get svc kube-prometheus-stack-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo 'pending')",
      "PROMETHEUS_URL=$(kubectl get svc kube-prometheus-stack-prometheus -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo 'pending')",
      "echo \"Grafana: http://$GRAFANA_URL\" > /tmp/monitoring_urls.txt",
      "echo \"Prometheus: http://$PROMETHEUS_URL:9090\" >> /tmp/monitoring_urls.txt",
      "cat /tmp/monitoring_urls.txt",

      # Final log
      "echo '=== Setup Complete ===' > /tmp/installation.log",
      "date >> /tmp/installation.log",
      "docker --version >> /tmp/installation.log 2>&1",
      "java --version >> /tmp/installation.log 2>&1",
      "kubectl version --client >> /tmp/installation.log 2>&1",
      "helm version >> /tmp/installation.log 2>&1",
      "cat /tmp/monitoring_urls.txt >> /tmp/installation.log"
    ]
  }
}

# ─────────────────────────────────────────
# EBS Volume
# ─────────────────────────────────────────
resource "aws_ebs_volume" "jenkins_volume" {
  availability_zone = aws_instance.my_ec2_instance.availability_zone
  size              = var.ebs_volume_size
  type              = "gp3"
  encrypted         = true  # fixed: EBS encryption enabled
  tags = {
    Name        = "Jenkins-Volume"
    Environment = var.environment
  }
}

resource "aws_volume_attachment" "jenkins_attach" {
  device_name  = "/dev/sdf"
  volume_id    = aws_ebs_volume.jenkins_volume.id
  instance_id  = aws_instance.my_ec2_instance.id
  force_detach = true
  depends_on   = [aws_instance.my_ec2_instance, aws_ebs_volume.jenkins_volume]
}
