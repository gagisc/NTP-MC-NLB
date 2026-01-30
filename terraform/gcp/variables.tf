variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "gcp_project_number" {
  description = "GCP Project Number (for budget alerts)"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for deployment"
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP zone for compute instances"
  type        = string
  default     = "us-central1-a"
}

variable "gcp_instance_type" {
  description = "GCP machine type (free tier: e2-micro)"
  type        = string
  default     = "e2-micro"
}

variable "gcp_subnet_cidr" {
  description = "CIDR block for GCP subnet"
  type        = string
  default     = "10.1.0.0/16"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Change to your IP for security
}

variable "aws_vpc_cidr_equiv" {
  description = "AWS VPC CIDR (for WireGuard rules)"
  type        = string
  default     = "10.0.0.0/16"
}

# WireGuard variables
variable "wireguard_gcp_private_key" {
  description = "WireGuard private key for GCP"
  type        = string
  sensitive   = true
}

variable "wireguard_gcp_public_key" {
  description = "WireGuard public key for GCP"
  type        = string
}

variable "wireguard_gcp_ip" {
  description = "WireGuard IP for GCP"
  type        = string
  default     = "192.168.10.2/32"
}

# K3s variables
variable "k3s_token" {
  description = "K3s cluster token"
  type        = string
  sensitive   = true
}

variable "aws_control_plane_ip" {
  description = "Public IP of AWS K3s control plane"
  type        = string
}

# Budget variables
variable "gcp_billing_account_id" {
  description = "GCP Billing Account ID"
  type        = string
}

variable "gcp_budget_limit" {
  description = "Monthly budget limit in USD"
  type        = number
  default     = 5
}

variable "gcp_notification_channels" {
  description = "Notification channel IDs for budget alerts"
  type        = list(string)
  default     = []
}
