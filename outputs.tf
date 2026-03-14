output "ec2_public_ip" {
  description = "Public IP of Jenkins EC2 instance"
  value       = aws_instance.my_ec2_instance.public_ip
}

output "ec2_public_dns" {
  description = "Public DNS of Jenkins EC2 instance"
  value       = aws_instance.my_ec2_instance.public_dns
}

output "jenkins_url" {
  description = "Jenkins URL"
  value       = "http://${aws_instance.my_ec2_instance.public_ip}:8080"
}

output "sonarqube_url" {
  description = "SonarQube URL"
  value       = "http://${aws_instance.my_ec2_instance.public_ip}:9000"
}

output "ecr_repository_url" {
  description = "ECR Repository URL"
  value       = aws_ecr_repository.my_ecr_repo.repository_url
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.vpc.id
}

output "eks_cluster_name" {
  description = "EKS Cluster Name"
  value       = aws_eks_cluster.eks.name
}

output "eks_cluster_endpoint" {
  description = "EKS Cluster Endpoint"
  value       = aws_eks_cluster.eks.endpoint
}

output "eks_cluster_version" {
  description = "EKS Cluster Kubernetes Version"
  value       = aws_eks_cluster.eks.version
}

output "eks_node_group_status" {
  description = "EKS Node Group Status"
  value       = aws_eks_node_group.eks_nodes.status
}

output "kubeconfig_command" {
  description = "Command to update kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.eks.name}"
}
