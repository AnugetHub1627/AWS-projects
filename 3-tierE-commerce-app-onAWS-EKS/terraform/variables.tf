# ==============================================================================
# VPC Name and CIDR Blocks
# ==============================================================================
variable "mtec_vpc_cidr" {
  type        = string
  description = "The main CIDR block allocated for the entire VPC infrastructure"
  default     = "10.0.0.0/16"
}

variable "mtec_vpc_name" {
  type        = string
  description = "The display tag name assigned to the base VPC"
  default     = "mtec-robot-shop-vpc"
}

variable "mtec_igw_name" {
  type        = string
  description = "The tag name assigned to the Internet Gateway"
  default     = "mtec-vpc-igw"
}

variable "mtec_nat_name" {
  type        = string
  description = "The tag name assigned to the outbound NAT Gateway"
  default     = "mtec-vpc-nat"
}

# ==============================================================================
# Public Subnets Properties
# ==============================================================================
variable "mtec_pub1a_cidr" {
  type        = string
  description = "CIDR block allocated for public subnet 1A"
  default     = "10.0.1.0/24"
}

variable "mtec_pub1a_name" {
  type        = string
  description = "Tag name for public subnet 1A"
  default     = "mtec-public-subnet-1a"
}

variable "mtec_pub1b_cidr" {
  type        = string
  description = "CIDR block allocated for public subnet 1B"
  default     = "10.0.2.0/24"
}

variable "mtec_pub1b_name" {
  type        = string
  description = "Tag name for public subnet 1B"
  default     = "mtec-public-subnet-1b"
}

# ==============================================================================
# Private Subnets Properties
# ==============================================================================
variable "mtec_pvt1a_cidr" {
  type        = string
  description = "CIDR block allocated for private subnet 1A"
  default     = "10.0.10.0/24"
}

variable "mtec_pvt1a_name" {
  type        = string
  description = "Tag name for private subnet 1A"
  default     = "mtec-private-subnet-1a"
}

variable "mtec_pvt1b_cidr" {
  type        = string
  description = "CIDR block allocated for private subnet 1B"
  default     = "10.0.20.0/24"
}

variable "mtec_pvt1b_name" {
  type        = string
  description = "Tag name for private subnet 1B"
  default     = "mtec-private-subnet-1b"
}
