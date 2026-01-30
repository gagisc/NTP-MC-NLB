#!/bin/bash
set -euo pipefail

# K3s Control Plane Setup Script for AWS
# This script installs K3s, WireGuard, and initializes the cluster

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

[Peer]
PublicKey = ${gcp_wireguard_pub_key}
AllowedIPs = ${gcp_wireguard_ip}
Endpoint = auto:51820
PersistentKeepalive = 25
EOF

sudo chmod 600 /etc/wireguard/wg0.conf

# Enable WireGuard
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

# Install K3s (latest stable)
export INSTALL_K3S_VERSION="${K3s_version:-}"
curl -sfL https://get.k3s.io | sh -s - \
  --cluster-init \
  --node-external-ip=$(ec2-metadata --public-ipv4 | cut -d " " -f 2) \
  --advertise-address=$(ec2-metadata --local-ipv4 | cut -d " " -f 2) \
  --bind-address=0.0.0.0 \
  --disable=traefik \
  --disable=servicelb \
  --disable=local-storage

# Wait for K3s to be ready
sudo /usr/local/bin/k3s kubectl wait --for=condition=Ready nodes --all --timeout=300s || true

# Install Calico for cross-cloud networking
sudo /usr/local/bin/k3s kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml || true
sleep 10
sudo /usr/local/bin/k3s kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml || true

# Wait for Calico
sudo /usr/local/bin/k3s kubectl wait --for=condition=Ready nodes --all --timeout=300s || true

# Install Metrics Server for HPA
sudo /usr/local/bin/k3s kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Create kubeconfig for remote access (stored in /tmp for Terraform to retrieve)
sudo cp /etc/rancher/k3s/k3s.yaml /tmp/kubeconfig
sudo chown $(id -u):$(id -g) /tmp/kubeconfig
sudo sed -i "s/127.0.0.1/$(ec2-metadata --public-ipv4 | cut -d ' ' -f 2)/g" /tmp/kubeconfig

# Install CloudWatch agent for monitoring
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
sudo rpm -U ./amazon-cloudwatch-agent.rpm

echo "K3s control plane setup complete!"
