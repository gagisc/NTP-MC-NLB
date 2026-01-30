variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "aws_vpc_cidr" {
  description = "CIDR block for AWS VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "aws_availability_zones" {
  description = "Availability zones for AWS subnets"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "aws_instance_type" {
  description = "EC2 instance type (free tier: t2.micro)"
  type        = string
  default     = "t2.micro"
}

variable "aws_agent_count" {
  description = "Number of K3s agent nodes in AWS"
  type        = number
  default     = 1

  validation {
    condition     = var.aws_agent_count >= 1
    error_message = "At least 1 agent node is required."
  }
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Change to your IP for security
}

variable "gcp_vpc_cidr_equiv" {
  description = "GCP VPC CIDR (for WireGuard peering rules)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "aws_budget_limit" {
  description = "Monthly budget limit in USD"
  type        = string
  default     = "5"
}

variable "alert_email_addresses" {
  description = "Email addresses for budget alerts"
  type        = list(string)
  default     = [] # Provide your email when using
}

# WireGuard variables
variable "wireguard_aws_private_key" {
  description = "WireGuard private key for AWS control plane"
  type        = string
  sensitive   = true
}

variable "wireguard_aws_public_key" {
  description = "WireGuard public key for AWS control plane"
  type        = string
}

variable "wireguard_aws_ip" {
  description = "WireGuard IP for AWS control plane"
  type        = string
  default     = "192.168.10.1/32"
}

variable "wireguard_gcp_ip" {
  description = "WireGuard IP for GCP"
  type        = string
  default     = "192.168.10.2/32"
}

variable "wireguard_gcp_public_key" {
  description = "WireGuard public key for GCP"
  type        = string
}

variable "wireguard_aws_agent_private_keys" {
  description = "WireGuard private keys for AWS agents"
  type        = list(string)
  sensitive   = true
  default     = []
}

variable "wireguard_aws_agent_public_keys" {
  description = "WireGuard public keys for AWS agents"
  type        = list(string)
  default     = []
}

variable "wireguard_aws_agent_ips" {
  description = "WireGuard IPs for AWS agents"
  type        = list(string)
  default     = []
}

# K3s variables
variable "k3s_token" {
  description = "K3s cluster token for agent nodes"
  type        = string
  sensitive   = true
}

variable "k3s_version" {
  description = "K3s version to deploy"
  type        = string
  default     = "v1.27.7"
}
