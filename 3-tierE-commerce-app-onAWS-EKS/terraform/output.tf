# ==============================================================================
# Network Outputs
# ==============================================================================
output "vpc_id" {
  description = "The Unique Identification code generated for your custom VPC"
  value       = aws_vpc.mtec_vpc.id
}

output "public_subnets" {
  description = "List containing IDs of all provisioned public subnets"
  value       = [aws_subnet.mtec_pub1a.id, aws_subnet.mtec_pub1b.id]
}

# ==============================================================================
# EC2 Server Connection Metrics
# ==============================================================================
output "web_tier_public_ip" {
  description = "The public facing IPv4 address of the Nginx/Web tier instance"
  value       = aws_instance.web.public_ip
}

output "app_tier_private_ip" {
  description = "The private network endpoint for the central microservice system"
  value       = aws_instance.app.private_ip
}

output "data_tier_private_ip" {
  description = "The private internal endpoint running the backend databases"
  value       = aws_instance.data.private_ip
}
