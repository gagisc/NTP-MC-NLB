# Root Terraform Variables

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_instance_type" {
  description = "AWS EC2 instance type (free tier: t2.micro)"
  type        = string
  default     = "t2.micro"
}

variable "aws_agent_count" {
  description = "Number of K3s agents in AWS"
  type        = number
  default     = 1
  validation {
    condition     = var.aws_agent_count >= 1
    error_message = "At least 1 AWS agent is required."
  }
}

variable "aws_vpc_cidr" {
  description = "AWS VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "gcp_project_number" {
  description = "GCP Project Number"
  type        = string
}

variable "gcp_region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP Zone"
  type        = string
  default     = "us-central1-a"
}

variable "gcp_instance_type" {
  description = "GCP machine type (free tier: e2-micro)"
  type        = string
  default     = "e2-micro"
}

variable "gcp_subnet_cidr" {
  description = "GCP Subnet CIDR"
  type        = string
  default     = "10.1.0.0/16"
}

variable "gcp_billing_account_id" {
  description = "GCP Billing Account ID"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "aws_budget_limit" {
  description = "AWS monthly budget limit (USD)"
  type        = string
  default     = "5"
}

variable "gcp_budget_limit" {
  description = "GCP monthly budget limit (USD)"
  type        = number
  default     = 5
}

variable "alert_email_addresses" {
  description = "Email addresses for AWS budget alerts"
  type        = list(string)
  default     = []
}

variable "gcp_notification_channels" {
  description = "GCP notification channel IDs"
  type        = list(string)
  default     = []
}

# WireGuard variables
variable "wireguard_aws_cp_ip" {
  description = "WireGuard IP for AWS Control Plane"
  type        = string
  default     = "192.168.10.1/32"
}

variable "wireguard_gcp_ip" {
  description = "WireGuard IP for GCP"
  type        = string
  default     = "192.168.10.2/32"
}

# K3s variables
variable "k3s_token" {
  description = "K3s cluster token (generate with: openssl rand -base64 32)"
  type        = string
  sensitive   = true
}

variable "k3s_version" {
  description = "K3s version to deploy"
  type        = string
  default     = "v1.27.7"
}
