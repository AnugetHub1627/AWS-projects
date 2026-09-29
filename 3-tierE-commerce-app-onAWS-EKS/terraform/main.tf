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
# 2. INTERNAL SECURITY GROUP FOR KUBEADM
# ==============================================================================
resource "aws_security_group" "k8s_sg" {
  name        = "mtec-kubeadm-cluster-sg"
  description = "Intra-cluster communications and administrative access boundaries"
  vpc_id      = aws_vpc.mtec_vpc.id

  # Open intra-cluster communications completely for nodes sharing this group
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true 
  }

  # Administrative SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # NodePort boundaries to review the final microservices web interface
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Clean outbound internet egress for updates, images, and SSM synchronization
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ==============================================================================
# 3. AWS IAM SECURITY PROLES (FOR AUTOMATED NODE INTERACTION)
# ==============================================================================
resource "aws_iam_role" "k8s_role" {
  name = "mtec-k8s-token-passing-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "://amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.k8s_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
}

resource "aws_iam_instance_profile" "k8s_profile" {
  name = "mtec-k8s-cluster-profile"
  role = aws_iam_role.k8s_role.name
}

# ==============================================================================
# 4. K8S CONTROL PLANE / MASTER NODE (c7i-flex.large in Public Subnet)
# ==============================================================================
resource "aws_instance" "master" {
  ami                    = "ami-03f4fa4574efb9720" # Ubuntu 22.04 LTS (ap-south-1 Mumbai specific)
  instance_type          = "c7i-flex.large"        # 2 vCPUs, 4GB RAM (Free-Tier Credit Valid)
  subnet_id              = aws_subnet.mtec_pub1a.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.k8s_profile.name
  key_name               = "your-mumbai-key-pair"  # Replace with your actual ap-south-1 key name

  tags = {
    Name = "k8s-master"
  }

  # EMBEDDING YOUR EXACT MASTER STEPS
  user_data = <<-EOF
              #!/bin/bash
              exec > >(tee /var/log/user-data.log|logger -t user-data -s2>/dev/tty) 2>&1

              # Step 1: Set hostname [1]
              hostnamectl set-hostname "k8smaster.example.net"

              # Step 2: Disable swap & Add kernel Parameters [1]
              swapoff -a
              sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

              tee /etc/modules-load.d/containerd.conf <<EOT
              overlay
              br_netfilter
              EOT
              modprobe overlay
              modprobe br_netfilter

              tee /etc/sysctl.d/kubernetes.conf <<EOT
              net.bridge.bridge-nf-call-ip6tables = 1
              net.bridge.bridge-nf-call-iptables = 1
              net.ipv4.ip_forward = 1
              EOT
              sysctl --system

              # Step 3: Update system and install basic utilities [1]
              apt-get update
              apt-get install -y apt-transport-https ca-certificates curl awscli

              # Step 4 & 5: Download signing keys and add the Kubernetes apt repository [1]
              mkdir -p /etc/apt/keyrings
              curl -fsSL https://k8s.io | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
              echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://k8s.io /' | tee /etc/apt/sources.list.d/kubernetes.list

              # Step 6: Install pinned versions from your specification sheet [1]
              apt-get update
              apt-get install -y kubelet=1.28.1-1.1 kubeadm=1.28.1-1.1 kubectl=1.28.1-1.1 docker.io
              apt-mark hold kubelet kubeadm kubectl docker.io

              # Step 7: Set the cgroup driver for runc to systemd [1]
              mkdir -p /etc/containerd
              containerd config default > /etc/containerd/config.toml
              sed -i 's/            SystemdCgroup = false/            SystemdCgroup = true/' /etc/containerd/config.toml
              systemctl restart containerd
              systemctl restart kubelet

              # Step 8: Initialize k8s cluster with user defined network [1]
              kubeadm config images pull
              kubeadm init --pod-network-cidr=192.168.0.0/16 > /tmp/kubeadm_out.txt

              # Step 9: Setup kubectl configuration for master user context [1]
              mkdir -p /home/ubuntu/.kube
              cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
              chown -R ubuntu:ubuntu /home/ubuntu/.kube/

              # Step 10 & 11: Setup Calico SDN [1]
              export KUBECONFIG=/etc/kubernetes/admin.conf
              kubectl create -f https://githubusercontent.com
              curl -L https://githubusercontent.com -o /tmp/custom-resources.yaml
              kubectl create -f /tmp/custom-resources.yaml

              # Capturing dynamic join string token and pushing it cleanly to AWS SSM Parameter store
              JOIN_CMD=$(tail -2 /tmp/kubeadm_out.txt | tr -d '\\\n')
              aws ssm put-parameter --name "/k8s/join_command" --value "$JOIN_CMD" --type "String" --overwrite --region ap-south-1
              EOF
}

# ==============================================================================
# 5. K8S WORKER NODES (t3.small across Private Subnets 1A and 1B)
# ==============================================================================
resource "aws_instance" "workers" {
  count                  = 3
  ami                    = "ami-03f4fa4574efb9720" # Ubuntu 22.04 LTS (ap-south-1 Mumbai)
  instance_type          = "t3.small"              # 2 vCPUs, 2GB RAM (Sufficient memory headroom for stateful components)
  
  # Distributes 3 worker instances cyclically across your 2 private subnets
  subnet_id              = count.index % 2 == 0 ? aws_subnet.mtec_pvt1a.id : aws_subnet.mtec_pvt1b.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.k8s_profile.name
  key_name               = "your-mumbai-key-pair"

  tags = {
    Name = "k8s-worker-${count.index + 1}"
  }

  depends_on = [aws_instance.master]

  # EMBEDDING YOUR EXACT WORKER STEPS
  user_data = <<-EOF
              #!/bin/bash
              exec > >(tee /var/log/user-data.log|logger -t user-data -s2>/dev/tty) 2>&1

              # Step 1: Assign hostnames sequentially [1]
              hostnamectl set-hostname "k8sworker${count.index + 1}.example.net"

              # Step 2: Disable swap & Add kernel Parameters [1]
              swapoff -a
              sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

              tee /etc/modules-load.d/containerd.conf <<EOT
              overlay
              br_netfilter
              EOT
              modprobe overlay
              modprobe br_netfilter

              tee /etc/sysctl.d/kubernetes.conf <<EOT
              net.bridge.bridge-nf-call-ip6tables = 1
              net.bridge.bridge-nf-call-iptables = 1
              net.ipv4.ip_forward = 1
              EOT
              sysctl --system

              # Step 3: Update system and utilities [1]
              apt-get update
              apt-get install -y apt-transport-https ca-certificates curl awscli

              # Step 4 & 5: Download signing keys and add the repository [1]
              mkdir -p /etc/apt/keyrings
              curl -fsSL https://k8s.io | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
              echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://k8s.io /' | tee /etc/apt/sources.list.d/kubernetes.list

              # Step 6: Install pinned runtime components [1]
              apt-get update
              apt-get install -y kubelet=1.28.1-1.1 kubeadm=1.28.1-1.1 docker.io
              apt-mark hold kubelet kubeadm docker.io

              # Step 7: Set cgroup driver to systemd for containerd [1]
              mkdir -p /etc/containerd
              containerd config default > /etc/containerd/config.toml
              sed -i 's/            SystemdCgroup = false/            SystemdCgroup = true/' /etc/containerd/config.toml
              systemctl restart containerd
              systemctl restart kubelet

              # Step 12: Wait for Master node to initialize and fetch dynamic join string token [1]
              while ! aws ssm get-parameter --name "/k8s/join_command" --region ap-south-1; do
                sleep 15
              done

              # Grab join command string from AWS parameter store records and self-execute
              JOIN_CMD=$(aws ssm get-parameter --name "/k8s/join_command" --query "Parameter.Value" --output text --region ap-south-1)
              eval $JOIN_CMD
              EOF
}


