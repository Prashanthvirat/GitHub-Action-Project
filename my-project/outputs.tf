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
