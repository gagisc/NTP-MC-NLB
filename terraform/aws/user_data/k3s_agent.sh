#!/bin/bash
set -euo pipefail

# K3s Agent Node Setup Script for AWS
# This script joins the node to an existing K3s cluster

# Update system
sudo yum update -y
sudo yum install -y curl wget git net-tools bind-utils htop

# Install WireGuard
sudo amazon-linux-extras install -y wireguard-tools
sudo modprobe wireguard

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

# Join K3s cluster
export K3S_URL="${k3s_server_url}"
export K3S_TOKEN="${k3s_token}"

curl -sfL https://get.k3s.io | sh -s - agent \
  --node-external-ip=$(ec2-metadata --public-ipv4 | cut -d " " -f 2) \
  --node-ip=$(ec2-metadata --local-ipv4 | cut -d " " -f 2)

echo "K3s agent setup complete!"
