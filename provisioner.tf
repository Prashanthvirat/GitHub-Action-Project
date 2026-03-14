# ─────────────────────────────────────────
# NULL RESOURCE — File Upload + Remote Exec
# ─────────────────────────────────────────
resource "null_resource" "ec2_setup" {
  depends_on = [
    aws_instance.my_ec2_instance,
    aws_volume_attachment.jenkins_attach
  ]

  triggers = {
    instance_id = aws_instance.my_ec2_instance.id
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = aws_instance.my_ec2_instance.public_ip
    private_key = file(var.private_key_path)
    timeout     = "15m"
  }

  # ── Upload tools.sh to EC2 ─────────────
  provisioner "file" {
    source      = "tools.sh"
    destination = "/home/ubuntu/tools.sh"
  }

  # ── Run tools.sh on EC2 ────────────────
  provisioner "remote-exec" {
    inline = [
      # Pass variables into the script via env
      "export AWS_REGION=${var.aws_region}",
      "export EKS_CLUSTER_NAME=${var.eks_cluster_name}",
      "export INSTANCE_TYPE=${var.instance_type}",
      "export ECR_URL=${aws_ecr_repository.my_ecr_repo.repository_url}",

      # Wait for cloud-init before running
      "cloud-init status --wait || true",

      "chmod +x /home/ubuntu/tools.sh",
      "/home/ubuntu/tools.sh",

      # Verify commands
      "docker --version",
      "java --version",
      "mvn --version",
      "aws --version",
      "kubectl version --client",
      "eksctl version"
    ]
  }

  # ── Print EC2 IP locally after apply ───
  provisioner "local-exec" {
    command = "echo 'Jenkins EC2 IP: ${aws_instance.my_ec2_instance.public_ip}'"
  }
}
