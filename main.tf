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
  image_tag_mutability = "MUTABLE"

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
  ebs_optimized          = true
  monitoring             = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

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
}

# ─────────────────────────────────────────
# EBS Volume
# ─────────────────────────────────────────
resource "aws_ebs_volume" "jenkins_volume" {
  availability_zone = aws_instance.my_ec2_instance.availability_zone
  size              = var.ebs_volume_size
  type              = "gp3"
  encrypted         = true
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
