terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Uncomment and configure for remote state (shared with AWS)
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "ntp-mc-nlb/gcp"
  # }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region

  user_project_override = false
  billing_project       = var.gcp_project_id
}

# VPC Network
resource "google_compute_network" "main" {
  name                    = "ntp-mc-nlb-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = []
}

# Subnet
resource "google_compute_subnetwork" "main" {
  name          = "ntp-mc-nlb-subnet"
  ip_cidr_range = var.gcp_subnet_cidr
  region        = var.gcp_region
  network       = google_compute_network.main.id

  private_ip_google_access = true
}

# Firewall - Allow SSH
resource "google_compute_firewall" "allow_ssh" {
  name    = "ntp-mc-nlb-allow-ssh"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.allowed_ssh_cidrs

  target_tags = ["k3s-node"]
}

# Firewall - Allow K3s API
resource "google_compute_firewall" "allow_k3s_api" {
  name    = "ntp-mc-nlb-allow-k3s-api"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["k3s-node"]
}

# Firewall - Allow WireGuard
resource "google_compute_firewall" "allow_wireguard" {
  name    = "ntp-mc-nlb-allow-wireguard"
  network = google_compute_network.main.name

  allow {
    protocol = "udp"
    ports    = ["51820"]
  }

  source_ranges = var.aws_vpc_cidr_equiv # Will update with AWS public IP range
  target_tags   = ["k3s-node"]
}

# Firewall - Allow NTP
resource "google_compute_firewall" "allow_ntp" {
  name    = "ntp-mc-nlb-allow-ntp"
  network = google_compute_network.main.name

  allow {
    protocol = "udp"
    ports    = ["123"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["k3s-node"]
}

# Firewall - Allow internal traffic
resource "google_compute_firewall" "allow_internal" {
  name    = "ntp-mc-nlb-allow-internal"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.gcp_subnet_cidr]
  target_tags   = ["k3s-node"]
}

# Get latest GCP image (Debian 12)
data "google_compute_image" "debian" {
  family  = "debian-12"
  project = "debian-cloud"
}

# Compute Instance for K3s Agent (e2-micro - always free tier eligible)
resource "google_compute_instance" "k3s_agent_gcp" {
  name         = "k3s-agent-gcp-1"
  machine_type = var.gcp_instance_type
  zone         = var.gcp_zone

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
      size  = 20
      type  = "pd-standard"
    }
  }

  # Additional disk for /var/lib/rancher
  attached_disk {
    source      = google_compute_disk.k3s_data.id
    device_name = "k3s-data"
  }

  network_interface {
    network            = google_compute_network.main.id
    subnetwork         = google_compute_subnetwork.main.id
    access_config {}   # Ephemeral public IP
  }

  service_account {
    email  = google_service_account.k3s.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = templatefile("${path.module}/user_data/k3s_agent_gcp.sh", {
    k3s_server_url        = "https://${var.aws_control_plane_ip}:6443"
    k3s_token             = var.k3s_token
    wireguard_private_key = var.wireguard_gcp_private_key
    wireguard_public_key  = var.wireguard_gcp_public_key
    wireguard_ip          = var.wireguard_gcp_ip
  })

  tags = ["k3s-node", "ntp-server"]

  labels = {
    environment = var.environment
    role        = "agent"
    cloud       = "gcp"
  }

  depends_on = []
}

# Persistent disk for K3s data
resource "google_compute_disk" "k3s_data" {
  name = "k3s-data-disk"
  type = "pd-standard"
  size = 20
  zone = var.gcp_zone
}

# Service Account for K3s nodes
resource "google_service_account" "k3s" {
  account_id   = "k3s-ntp-server"
  display_name = "K3s NTP Server Service Account"
}

# IAM binding for monitoring
resource "google_project_iam_member" "monitoring_metric_writer" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.k3s.email}"
}

# Budget Alert for GCP
resource "google_billing_budget" "monthly_free_tier" {
  billing_account = var.gcp_billing_account_id
  display_name    = "NTP-MC-NLB Free Tier Limit"

  budget_filter {
    projects = ["projects/${var.gcp_project_number}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      nanos         = 0
      units         = var.gcp_budget_limit
    }
  }

  threshold_rule {
    threshold_percent = 0.5
  }

  threshold_rule {
    threshold_percent = 0.8
  }

  threshold_rule {
    threshold_percent = 1.0
  }

  all_updates_rule {
    monitoring_notification_channels = var.gcp_notification_channels
    pubsub_topic                     = google_pubsub_topic.budget_alerts.id
    disable_default_iam_recipients   = false
  }
}

# Pub/Sub Topic for budget alerts
resource "google_pubsub_topic" "budget_alerts" {
  name = "ntp-budget-alerts"
}

# Output values
output "k3s_agent_ip" {
  description = "Public IP of GCP K3s agent"
  value       = google_compute_instance.k3s_agent_gcp.network_interface[0].access_config[0].nat_ip
}

output "k3s_agent_private_ip" {
  description = "Private IP of GCP K3s agent"
  value       = google_compute_instance.k3s_agent_gcp.network_interface[0].network_ip
}

output "vpc_name" {
  description = "VPC network name"
  value       = google_compute_network.main.name
}

output "subnet_cidr" {
  description = "Subnet CIDR block"
  value       = google_compute_subnetwork.main.ip_cidr_range
}
