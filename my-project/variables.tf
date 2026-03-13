variable "aws_access_key" {
  description = "AWS Access Key ID"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS Secret Access Key"
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-south-1"
}

variable "key_pair_name" {
  description = "EC2 Key Pair Name"
  type        = string
}

variable "private_key_path" {
  description = "Path to the private key file on the runner"
  type        = string
  default     = "/tmp/ec2_key.pem"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "c7i-flex.large"
}

variable "ebs_volume_size" {
  description = "EBS volume size in GB"
  type        = number
  default     = 100
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "balu-cluster22"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}
