# Root Terraform Configuration - Orchestrates AWS, GCP, and WireGuard deployment
# This is the main entry point for deploying the multi-cloud NTP server

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Uncomment for remote state management
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "ntp-mc-nlb/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

# Generate WireGuard keys
module "wireguard" {
  source = "./wireguard"

  aws_agent_count = var.aws_agent_count
}

# AWS Infrastructure
module "aws" {
  source = "./aws"

  aws_region                    = var.aws_region
  aws_instance_type             = var.aws_instance_type
  aws_agent_count               = var.aws_agent_count
  aws_vpc_cidr                  = var.aws_vpc_cidr
  environment                   = var.environment
  allowed_ssh_cidrs             = var.allowed_ssh_cidrs
  aws_budget_limit              = var.aws_budget_limit
  alert_email_addresses         = var.alert_email_addresses

  # WireGuard config
  wireguard_aws_private_key     = module.wireguard.wireguard_aws_cp_private_key
  wireguard_aws_public_key      = "" # Will be generated in wireguard module
  wireguard_aws_ip              = var.wireguard_aws_cp_ip
  wireguard_gcp_ip              = var.wireguard_gcp_ip
  wireguard_gcp_public_key      = "" # Will be provided by GCP module

  # Agent WireGuard
  wireguard_aws_agent_private_keys = module.wireguard.wireguard_aws_agent_private_keys
  wireguard_aws_agent_public_keys  = []
  wireguard_aws_agent_ips          = module.wireguard.wireguard_config_data.aws_agent_ips

  # K3s config
  k3s_token = var.k3s_token
  k3s_version = var.k3s_version

  depends_on = [module.wireguard]
}

# GCP Infrastructure
module "gcp" {
  source = "./gcp"

  gcp_project_id           = var.gcp_project_id
  gcp_project_number       = var.gcp_project_number
  gcp_region               = var.gcp_region
  gcp_zone                 = var.gcp_zone
  gcp_instance_type        = var.gcp_instance_type
  gcp_subnet_cidr          = var.gcp_subnet_cidr
  environment              = var.environment
  allowed_ssh_cidrs        = var.allowed_ssh_cidrs
  gcp_budget_limit         = var.gcp_budget_limit
  gcp_notification_channels = var.gcp_notification_channels
  gcp_billing_account_id   = var.gcp_billing_account_id

  # WireGuard config
  wireguard_gcp_private_key = module.wireguard.wireguard_gcp_private_key
  wireguard_gcp_public_key  = "" # Will be generated
  wireguard_gcp_ip          = var.wireguard_gcp_ip
  aws_vpc_cidr_equiv        = var.aws_vpc_cidr

  # K3s config
  k3s_token            = var.k3s_token
  aws_control_plane_ip = module.aws.k3s_control_plane_ip

  depends_on = [module.wireguard, module.aws]
}

# Outputs
output "aws_control_plane_ip" {
  description = "AWS K3s Control Plane Public IP"
  value       = module.aws.k3s_control_plane_ip
}

output "aws_agent_ips" {
  description = "AWS K3s Agent Public IPs"
  value       = module.aws.k3s_agents_ips
}

output "gcp_agent_ip" {
  description = "GCP K3s Agent Public IP"
  value       = module.gcp.k3s_agent_ip
}

output "k3s_cluster_info" {
  description = "K3s Cluster Information"
  value = {
    control_plane_ip = module.aws.k3s_control_plane_ip
    control_plane_url = "https://${module.aws.k3s_control_plane_ip}:6443"
    agent_nodes_aws = module.aws.k3s_agents_ips
    agent_node_gcp = module.gcp.k3s_agent_ip
  }
}

output "wireguard_config" {
  description = "WireGuard Configuration Summary"
  value       = module.wireguard.wireguard_config_data
  sensitive   = false
}
