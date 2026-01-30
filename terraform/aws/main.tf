terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  # Uncomment and configure for remote state
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "ntp-mc-nlb/aws/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "NTP-MC-NLB"
      ManagedBy   = "Terraform"
      CreatedAt   = timestamp()
    }
  }
}

# VPC and Networking
module "vpc" {
  source = "./modules/vpc"

  vpc_cidr            = var.aws_vpc_cidr
  availability_zones  = var.aws_availability_zones
  environment         = var.environment
  project_name        = "ntp-mc-nlb"
}

# Security Group for K3s Control Plane
resource "aws_security_group" "k3s_control_plane" {
  name_prefix = "k3s-cp-"
  description = "Security group for K3s control plane"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "k3s-control-plane-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Allow SSH
resource "aws_security_group_rule" "allow_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.allowed_ssh_cidrs
  security_group_id = aws_security_group.k3s_control_plane.id
}

# Allow K3s API server
resource "aws_security_group_rule" "allow_k3s_api" {
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k3s_control_plane.id
}

# Allow WireGuard
resource "aws_security_group_rule" "allow_wireguard" {
  type              = "ingress"
  from_port         = 51820
  to_port           = 51820
  protocol          = "udp"
  cidr_blocks       = var.gcp_vpc_cidr_equiv # Will be replaced by GCP CIDR after routing setup
  security_group_id = aws_security_group.k3s_control_plane.id
}

# Allow internal cluster communication
resource "aws_security_group_rule" "allow_internal" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  self              = true
  security_group_id = aws_security_group.k3s_control_plane.id
}

resource "aws_security_group_rule" "allow_internal_udp" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "udp"
  self              = true
  security_group_id = aws_security_group.k3s_control_plane.id
}

# Allow NTP service (UDP port 123)
resource "aws_security_group_rule" "allow_ntp" {
  type              = "ingress"
  from_port         = 123
  to_port           = 123
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k3s_control_plane.id
}

# Allow egress to all
resource "aws_security_group_rule" "allow_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k3s_control_plane.id
}

# EC2 Instance for K3s Control Plane (t2.micro - free tier eligible)
resource "aws_instance" "k3s_control_plane" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = var.aws_instance_type
  subnet_id                   = module.vpc.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.k3s_control_plane.id]
  associate_public_ip_address = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
    tags = {
      Name = "k3s-control-plane-root"
    }
  }

  # Add EBS volume for /var/lib/rancher (K3s data)
  ebs_block_device {
    device_name           = "/dev/sdf"
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
    tags = {
      Name = "k3s-control-plane-data"
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data/k3s_control_plane.sh", {
    wireguard_private_key = var.wireguard_aws_private_key
    wireguard_public_key  = var.wireguard_aws_public_key
    wireguard_ip          = var.wireguard_aws_ip
    gcp_wireguard_ip      = var.wireguard_gcp_ip
    gcp_wireguard_pub_key = var.wireguard_gcp_public_key
  }))

  tags = {
    Name = "k3s-control-plane-aws"
    Role = "control-plane"
  }

  depends_on = [module.vpc]

  monitoring = true
}

# Get latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# Elastic IP for Control Plane
resource "aws_eip" "k3s_control_plane" {
  instance = aws_instance.k3s_control_plane.id
  domain   = "vpc"

  tags = {
    Name = "k3s-control-plane-eip"
  }

  depends_on = [module.vpc]
}

# EC2 Instance for K3s Agent (Worker Node)
resource "aws_instance" "k3s_agent_aws" {
  count                       = var.aws_agent_count
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = var.aws_instance_type
  subnet_id                   = module.vpc.public_subnet_ids[count.index % length(module.vpc.public_subnet_ids)]
  vpc_security_group_ids      = [aws_security_group.k3s_control_plane.id]
  associate_public_ip_address = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(templatefile("${path.module}/user_data/k3s_agent.sh", {
    k3s_server_url        = "https://${aws_eip.k3s_control_plane.public_ip}:6443"
    k3s_token             = var.k3s_token
    wireguard_private_key = var.wireguard_aws_agent_private_keys[count.index]
    wireguard_public_key  = var.wireguard_aws_agent_public_keys[count.index]
    wireguard_ip          = var.wireguard_aws_agent_ips[count.index]
  }))

  tags = {
    Name = "k3s-agent-aws-${count.index + 1}"
    Role = "agent"
  }

  depends_on = [aws_instance.k3s_control_plane]
}

# CloudWatch Log Group for monitoring
resource "aws_cloudwatch_log_group" "k3s_logs" {
  name              = "/aws/k3s/ntp-mc-nlb"
  retention_in_days = 7

  tags = {
    Name = "k3s-logs"
  }
}

# AWS Budgets for cost alerting
resource "aws_budgets_budget" "monthly_free_tier" {
  name              = "NTP-MC-NLB-Free-Tier-Limit"
  budget_type       = "COST"
  limit_unit        = "USD"
  limit_value       = var.aws_budget_limit
  time_period_start = formatdate("YYYY-MM-01", timestamp())
  time_period_end   = formatdate("YYYY-MM-01", timeadd(timestamp(), "2160h")) # ~3 months
  time_unit         = "MONTHLY"

  cost_filter {
    name   = "Service"
    values = ["Amazon Elastic Compute Cloud - Compute", "AWS Lambda", "EC2 - Other", "EBS"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    notification_type          = "FORECASTED"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_behavior      = "DEFAULT_NOTIFICATION"
    subscriber_email_addresses = var.alert_email_addresses
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    notification_type          = "ACTUAL"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_behavior      = "DEFAULT_NOTIFICATION"
    subscriber_email_addresses = var.alert_email_addresses
  }
}

# Output the control plane IP for WireGuard and K3s access
output "k3s_control_plane_ip" {
  description = "Public IP of K3s control plane"
  value       = aws_eip.k3s_control_plane.public_ip
}

output "k3s_control_plane_private_ip" {
  description = "Private IP of K3s control plane"
  value       = aws_instance.k3s_control_plane.private_ip
}

output "k3s_agents_ips" {
  description = "Public IPs of K3s agent nodes"
  value       = aws_instance.k3s_agent_aws[*].public_ip
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = var.aws_vpc_cidr
}
