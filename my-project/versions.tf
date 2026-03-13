terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }

  # Remote backend — replace bucket/table names with your own
  backend "s3" {
    # These values are passed via -backend-config in CI
    # bucket         = "your-tf-state-bucket"
    # key            = "terraform/jenkins-eks/terraform.tfstate"
    # region         = "ap-south-1"
    # dynamodb_table = "your-tf-lock-table"
    # encrypt        = true
  }
}
