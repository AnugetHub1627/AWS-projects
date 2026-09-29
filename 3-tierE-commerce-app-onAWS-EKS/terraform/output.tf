# ==============================================================================
# Network Outputs
# ==============================================================================
output "vpc_id" {
  description = "The Unique Identification code generated for your custom VPC"
  value       = aws_vpc.mtec_vpc.id
}
# ==============================================================================
# 6. MANAGEMENT INTERFACE OUTPUTS
# ==============================================================================
output "master_public_ip" {
  description = "Administrative Public IP address of the Control Plane Master"
  value       = aws_instance.master.public_ip
}


output "public_subnets" {
  description = "List containing IDs of all provisioned public subnets"
  value       = [aws_subnet.mtec_pub1a.id, aws_subnet.mtec_pub1b.id]
}
# ==============================================================================
# TERMINAL ACCESS & MANAGEMENT OUTPUTS
# ==============================================================================

output "master_public_ip" {
  description = "The public IP address of your K8s Master Node. Use this to configure your local kubectl or to SSH directly into the cluster control plane."
  value       = aws_instance.master.public_ip
}

output "master_ssh_command" {
  description = "Run this exact command in your terminal to SSH straight into your Kubernetes Master Node."
  value       = "ssh -i 'your-mumbai-key-pair.pem' ubuntu@${aws_instance.master.public_ip}"
}

output "master_private_ip" {
  description = "The internal AWS Private IP of your Master Control Plane."
  value       = aws_instance.master.private_ip
}

output "worker_nodes_private_ips" {
  description = "The internal AWS Private IPs assigned to your 3 Worker Nodes inside the Private Subnets."
  value       = aws_instance.workers[*].private_ip
}

output "cluster_validation_command" {
  description = "Once logged into your Master node, run this command to watch your nodes join the cluster dynamically in real-time."
  value       = "watch -n2 kubectl get nodes -o wide"
}
