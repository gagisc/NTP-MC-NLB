# WireGuard VPN Configuration for Cross-Cloud Connectivity
# This Terraform configuration generates WireGuard keys and creates peer configurations

terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Generate WireGuard keys for AWS Control Plane
resource "tls_private_key" "wireguard_aws_cp" {
  algorithm = "ED25519"
}

resource "random_password" "wireguard_aws_cp_key" {
  length  = 44
  special = false

  provisioner "local-exec" {
    command = <<-EOT
      echo '${random_password.wireguard_aws_cp_key.result}' | wg pubkey > /tmp/aws_cp_pubkey.txt
    EOT
  }
}

# Generate WireGuard keys for GCP Agent
resource "random_password" "wireguard_gcp_key" {
  length  = 44
  special = false

  provisioner "local-exec" {
    command = <<-EOT
      echo '${random_password.wireguard_gcp_key.result}' | wg pubkey > /tmp/gcp_pubkey.txt
    EOT
  }
}

# AWS Agent keys (for multiple agents)
resource "random_password" "wireguard_aws_agent_keys" {
  count   = var.aws_agent_count
  length  = 44
  special = false
}

# Local values for storing generated keys
locals {
  wireguard_configs = {
    aws_cp = {
      private_key = random_password.wireguard_aws_cp_key.result
      ip          = var.wireguard_aws_cp_ip
    }
    gcp = {
      private_key = random_password.wireguard_gcp_key.result
      ip          = var.wireguard_gcp_ip
    }
    aws_agents = [
      for i, key in random_password.wireguard_aws_agent_keys : {
        private_key = key.result
        ip          = cidrhost(var.wireguard_subnet, i + 3)
      }
    ]
  }
}

# Output WireGuard configuration
output "wireguard_aws_cp_private_key" {
  description = "AWS Control Plane WireGuard private key"
  value       = random_password.wireguard_aws_cp_key.result
  sensitive   = true
}

output "wireguard_gcp_private_key" {
  description = "GCP WireGuard private key"
  value       = random_password.wireguard_gcp_key.result
  sensitive   = true
}

output "wireguard_aws_agent_private_keys" {
  description = "AWS Agent WireGuard private keys"
  value       = random_password.wireguard_aws_agent_keys[*].result
  sensitive   = true
}

output "wireguard_config_data" {
  description = "WireGuard configuration data for reference"
  value = {
    aws_cp_ip    = var.wireguard_aws_cp_ip
    gcp_ip       = var.wireguard_gcp_ip
    aws_agent_ips = [for i in range(var.aws_agent_count) : cidrhost(var.wireguard_subnet, i + 3)]
  }
  sensitive = false
}
