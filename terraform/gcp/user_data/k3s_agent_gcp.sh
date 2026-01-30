#!/bin/bash
set -euo pipefail

# K3s Agent Node Setup Script for GCP
# This script joins the node to an existing K3s cluster

# Update system
sudo apt-get update
sudo apt-get install -y curl wget git net-tools dnsutils htop

# Install WireGuard
sudo apt-get install -y wireguard wireguard-tools

# Create WireGuard configuration
sudo mkdir -p /etc/wireguard
sudo tee /etc/wireguard/wg0.conf > /dev/null <<EOF
[Interface]
PrivateKey = ${wireguard_private_key}
Address = ${wireguard_ip}
ListenPort = 51820
EOF

sudo chmod 600 /etc/wireguard/wg0.conf

# Enable WireGuard
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

# Get instance metadata
INTERNAL_IP=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip -H "Metadata-Flavor: Google")
EXTERNAL_IP=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H "Metadata-Flavor: Google")

# Join K3s cluster
export K3S_URL="${k3s_server_url}"
export K3S_TOKEN="${k3s_token}"

curl -sfL https://get.k3s.io | sh -s - agent \
  --node-external-ip=$EXTERNAL_IP \
  --node-ip=$INTERNAL_IP

echo "K3s agent setup complete!"
