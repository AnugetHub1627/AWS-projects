provider "aws" {
  region = "ap-south-1"
  #profile = "default"
}

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# ==============================================================================
# 1. NETWORK TOPOLOGY (Multi-AZ VPC for EKS Integration)
# ==============================================================================
resource "aws_vpc" "mtec_vpc" {
  cidr_block           = var.mtec_vpc_cidr
  enable_dns_hostnames = true

  tags = {
    Name                                       = var.mtec_vpc_name
    "kubernetes.io/cluster/mtec_EKS" = "shared"
  }
}

resource "aws_internet_gateway" "mtec_igw" {
  vpc_id = aws_vpc.mtec_vpc.id

  tags = {
    Name = var.mtec_igw_name
  }
}

# Public Subnets (Minimum 2 required across 2 distinct AZs for EKS)
resource "aws_subnet" "mtec_pub1a" {
  vpc_id                  = aws_vpc.mtec_vpc.id
  cidr_block              = var.mtec_pub1a_cidr
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name                              = var.mtec_pub1a_name
    "kubernetes.io/cluster/mtec_EKS" = "shared"
    "kubernetes.io/role/elb"          = "1"
  }
}

resource "aws_subnet" "mtec_pub1b" {
  vpc_id                  = aws_vpc.mtec_vpc.id
  cidr_block              = var.mtec_pub1b_cidr
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = true

  tags = {
    Name                              = var.mtec_pub1b_name
    "kubernetes.io/cluster/mtec_EKS" = "shared"
    "kubernetes.io/role/elb"          = "1"
  }
}

# Private Subnets (Where EKS Nodes safely execute microservice containers)
resource "aws_subnet" "mtec_pvt1a" {
  vpc_id            = aws_vpc.mtec_vpc.id
  cidr_block        = var.mtec_pvt1a_cidr
  availability_zone = "ap-south-1a"

  tags = {
    Name                              = var.mtec_pvt1a_name
    "kubernetes.io/cluster/mtec_EKS" = "shared"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "mtec_pvt1b" {
  vpc_id            = aws_vpc.mtec_vpc.id
  cidr_block        = var.mtec_pvt1b_cidr
  availability_zone = "ap-south-1b"

  tags = {
    Name                              = var.mtec_pvt1b_name
    "kubernetes.io/cluster/mtec_EKS" = "shared"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# NAT Gateway Infrastructure
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "mtec_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.mtec_pub1a.id

  tags = {
    Name = var.mtec_nat_name
  }
}

# Routing Tables and Subnet Associations
resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.mtec_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mtec_igw.id
  }
}

resource "aws_route_table" "private-rt" {
  vpc_id = aws_vpc.mtec_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.mtec_nat.id
  }
}

resource "aws_route_table_association" "ass_pub_1a" {
  subnet_id      = aws_subnet.mtec_pub1a.id
  route_table_id = aws_route_table.public-rt.id
}

resource "aws_route_table_association" "ass_pub_1b" {
  subnet_id      = aws_subnet.mtec_pub1b.id
  route_table_id = aws_route_table.public-rt.id
}

resource "aws_route_table_association" "pvt_1a" {
  subnet_id      = aws_subnet.mtec_pvt1a.id
  route_table_id = aws_route_table.private-rt.id
}

resource "aws_route_table_association" "pvt_1b" {
  subnet_id      = aws_subnet.mtec_pvt1b.id
  route_table_id = aws_route_table.private-rt.id
}

# ==============================================================================
# 2. STANDALONE SONARQUBE & DOCKER ENGINE SERVER
# ==============================================================================
resource "aws_security_group" "web_sg" {
  name   = "web-tier-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Open to the public web
  }
   ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # SSH Access (restrict to your IP in prod)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "app_sg" {
  name   = "app-tier-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.web_sg.id] # Only Web-tier can talk to App-tier
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "data_sg" {
  name   = "data-tier-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.app_sg.id] # Only App-tier can talk to Data-tier
  }
   egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
# 3. Bootstrap Script to install Docker & Docker Compose automatically
locals {
  user_data = <<-EOT
    #!/bin/bash
    sudo apt-get update -y
    sudo apt-get install -y docker.io docker-compose git
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker ubuntu
  EOT
}
# 4. EC2 Instances 
resource "aws_instance" "web" {
  ami                    = "ami-0e2c8caa4b6378d8c" # Ubuntu 24.04 LTS AMI (Double check yours)
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  user_data              = local.user_data
  tags                   = { Name = "RobotShop-Web-Tier" }
}
resource "aws_instance" "app" {
  ami                    = "ami-0e2c8caa4b6378d8c"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  user_data              = local.user_data
  tags                   = { Name = "RobotShop-App-Tier" }
}
resource "aws_instance" "data" {
  ami                    = "ami-0e2c8caa4b6378d8c"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.data_sg.id]
  user_data              = local.user_data
  tags                   = { Name = "RobotShop-Data-Tier" }
}
