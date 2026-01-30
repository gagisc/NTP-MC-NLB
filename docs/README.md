# NTP Multi-Cloud Load Balanced (NTP-MC-NLB) Infrastructure

A production-ready, cost-optimized, multi-cloud NTP server infrastructure spanning AWS and GCP using Kubernetes (K3s), WireGuard VPN, Terraform, and automated cost controls. Designed to maintain free tier eligibility during trial period and remain low-cost thereafter.

## 🎯 Project Goals

- **Kubernetes Element**: Single K3s cluster spanning AWS and GCP with cross-cloud networking
- **Cost Optimization**: Stay within free tier during trial (~$0); estimated $92/month after
- **High Availability**: Stratum 2 NTP server compliant with pool.ntp.org requirements
- **Automated Management**: Infrastructure-as-Code (Terraform), configuration automation (Ansible), orchestration (Kubernetes)
- **Observability**: Prometheus + Grafana monitoring, cost tracking, alerting

## 📋 Architecture Overview

### Cloud Topology

```
┌─────────────────────────────────────────────────────────┐
│                    Internet (Public)                    │
│              pool.ntp.org Registration                  │
└─────────────────────────────────────────────────────────┘
          │                                      │
          ▼                                      ▼
    ┌──────────────────┐              ┌──────────────────┐
    │   AWS (us-east-1)│              │ GCP (us-central1)│
    │                  │              │                  │
    │ t2.micro         │              │ e2-micro (ALF)   │
    │ Control Plane +  │◄─WireGuard──►│ Agent Node       │
    │ 1x Agent         │   VPN(UDP)   │                  │
    │ Elastic IP       │   Port 51820 │ Ephemeral IP     │
    └──────────────────┘              └──────────────────┘
         │                                     │
         │ NTP Service                         │
         │ Port 123 (UDP)                      │
         │ IPv4 + IPv6                         │
         └─────────────┬───────────────────────┘
                       │
              ┌────────▼────────┐
              │  NTP Pool       │
              │  Monitoring     │
              └─────────────────┘
```

### Network Architecture

```
WireGuard VPN Bridge (192.168.10.0/24)
├── AWS Control Plane: 192.168.10.1/32
├── AWS Agents: 192.168.10.3+/32
└── GCP Agent: 192.168.10.2/32

K3s Cluster (Pod Network via Calico)
├── Pod CIDR: 10.0.0.0/8 (configurable)
├── Service CIDR: 10.43.0.0/16
├── NTP Pods: Distributed across AWS/GCP
├── Prometheus: Metrics collection
├── Grafana: Visualization
└── Metrics Server: HPA support
```

### Service Architecture

```
NTP Service Deployment
├── Deployment: 2-10 replicas (auto-scaling)
│   ├── NTP Server Container (cturra/ntp:latest)
│   ├── RFC 5905 Compliant
│   ├── Stratum 2 via pool.ntp.org upstreams
│   └── Health checks (ntpq probes)
├── Service: LoadBalancer type
│   ├── Port 123/UDP
│   ├── External IP (AWS/GCP assigned)
│   └── IPv6 support
├── PodDisruptionBudget: Min 1 available
└── NetworkPolicy: DDoS protection, access control
```

## 🚀 Getting Started

### Prerequisites

**Local Machine:**
- Terraform >= 1.0
- kubectl >= 1.27
- Ansible >= 2.10
- AWS CLI configured with credentials
- GCP SDK (gcloud) configured with credentials
- SSH key pair for EC2 access

**Cloud Requirements:**
- AWS Account with free tier eligibility
- GCP Account with free tier eligibility
- Billing account configured on both

### 1. Clone & Configure

```bash
cd NTP-MC-NLB
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars`:

```hcl
# Fill in your values
gcp_project_id        = "your-actual-project-id"
gcp_project_number    = "123456789"
gcp_billing_account_id = "01ABCD-EFGH12-IJ3KL4"
alert_email_addresses = ["your-email@example.com"]
k3s_token            = "$(openssl rand -base64 32)"
```

### 2. Generate K3s Token

```bash
K3S_TOKEN=$(openssl rand -base64 32)
# Add to terraform.tfvars
```

### 3. Deploy Infrastructure

```bash
cd terraform

# Validate configuration
terraform validate

# Plan deployment
terraform plan -out=tfplan

# Apply (this takes 5-10 minutes)
terraform apply tfplan
```

**Output will include:**
- AWS control plane IP
- GCP agent IP
- K3s cluster endpoint
- WireGuard configuration

### 4. Configure Kubeconfig

```bash
# After Terraform completes, retrieve kubeconfig
mkdir -p ~/.kube
aws s3 cp s3://your-bucket/kubeconfig ~/.kube/config-ntp # or via SCP

# Merge into existing kubeconfig if needed
export KUBECONFIG=~/.kube/config:~/.kube/config-ntp
kubectl config view --flatten > ~/.kube/config_merged
mv ~/.kube/config_merged ~/.kube/config
```

### 5. Deploy K3s Applications

```bash
# Run Ansible playbook to configure cluster
cd ../ansible
ansible-playbook k3s_cluster_setup.yml -i inventory.ini

# Update inventory.ini with actual IPs first!
```

### 6. Verify Deployment

```bash
# Check cluster status
kubectl get nodes -o wide

# Check NTP deployment
kubectl -n ntp-server get pods
kubectl -n ntp-server get svc

# View Grafana (default password: admin)
kubectl -n monitoring port-forward svc/grafana 3000:3000
# Visit http://localhost:3000
```

## 📊 Monitoring & Observability

### Prometheus

Collects metrics from:
- Kubernetes API server, nodes, pods
- NTP server pods (stratum, offset, jitter, frequency)
- Container metrics (CPU, memory, disk I/O)
- Custom exporters

**Access:**
```bash
kubectl -n monitoring port-forward svc/prometheus 9090:9090
# http://localhost:9090
```

### Grafana

Pre-configured dashboards for:
- K3s Cluster Status
- NTP Server Health
- Pod Resource Utilization
- Cross-cloud Network Stats

**Access:**
```bash
kubectl -n monitoring port-forward svc/grafana 3000:3000
# http://localhost:3000 (admin/admin)
```

### Key NTP Metrics

| Metric | Description | Target | Alert |
|--------|-------------|--------|-------|
| Stratum | NTP clock layer | 2 (Stratum 2 server) | >3 = critical |
| Offset | Time difference to upstream | <10ms | >50ms = warning |
| Jitter | Variation in samples | <50ms | >100ms = warning |
| Frequency | Oscillator error | <5 ppm | >10 ppm = warning |
| Uptime | Pod uptime | 99%+ | <95% = critical |

## 💰 Cost Management

### Free Tier Strategy

**AWS (12 months free):**
- t2.micro: 750 hours/month ✓ Always free
- 100 GB data transfer out/month
- EBS: 30 GB gp2

**GCP (Always free):**
- e2-micro: 1 instance, 730 hours/month ✓ Always free
- 1 GB egress to Internet/month (Premium Tier)
- 5 GB Cloud Storage

**Cost Rotation (to maintain free tier):**
- AWS runs Mon-Wed (16 hours/day) = 480 hours/month < 750 free
- GCP runs Thu-Sun (varies) = 250 hours/month < 730 free
- Overlap on weekends provides redundancy

### Post-Free Tier Costs (Monthly)

| Component | Cost |
|-----------|------|
| AWS t2.micro | $8.47 |
| AWS EBS (20 GB) | $2.00 |
| GCP e2-micro | $17.37 |
| GCP Disk (20 GB) | $0.80 |
| Data transfer (100 GB) | $21.00 |
| **Total** | **~$49.64** |

*Note: Load balancer costs ($23/month) excluded. Direct IPs used instead for cost savings.*

### Cost Monitoring

```bash
# Check current costs
./scripts/cost_monitoring.sh check

# Continuous monitoring (hourly)
./scripts/cost_monitoring.sh monitor

# Display cost report
./scripts/cost_monitoring.sh report
```

**AWS Budget Alerts:**
- Triggered at 50%, 80%, 100% of limit
- Sent to alert_email_addresses
- Based on monthly spend

**GCP Budget Alerts:**
- Configured in GCP Console
- Pub/Sub notifications
- Custom thresholds

### Emergency Shutdown

If costs exceed limits:

```bash
# Emergency shutdown (destroys all infrastructure)
./scripts/emergency_shutdown.sh

# Confirm with "I UNDERSTAND"
```

**This will:**
- Terminate all EC2 instances
- Delete GCP compute instances
- Release Elastic IPs
- Delete VPCs
- Backup Terraform state

## 🔧 Automation Scripts

### Instance Scheduler

Rotates instances based on cost vs. free tier availability:

```bash
# Manual scheduling
./scripts/instance_scheduler.sh all your-gcp-project

# Automated via cron (runs daily)
0 0 * * * /path/to/instance_scheduler.sh all your-gcp-project
```

**Schedule Logic:**
- Mon-Wed: AWS on, GCP off (leverages AWS 750 hours/month)
- Thu-Sun: GCP on, AWS partial (GCP 730 hours/month)
- Weekends: Both potentially running for redundancy

### Cost Monitoring Service

```bash
# Start monitoring in background
./scripts/cost_monitoring.sh monitor &

# Logs to: logs/cost_monitoring.log
```

## 🌐 NTP Pool Registration

### Prerequisites

- Static public IPv4 and IPv6 addresses (✓ in deployment)
- 24/7 uptime (achieved via redundancy)
- RFC 5905 NTPv4 compliance (✓ via cturra/ntp image)
- Upstream Stratum 1 servers (✓ configured)

### Registration Steps

1. **Internal Testing (48+ hours)**
   ```bash
   # Monitor NTP metrics
   ntpq -p
   ntpstat
   ```

2. **External Monitoring**
   ```bash
   # Use public monitoring tools
   ntpdate -q $(kubectl get svc -n ntp-server -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
   ```

3. **Register with pool.ntp.org**
   - Visit https://manage.ntppool.org/
   - Add server IP and IPv6
   - Verify stratum and accuracy
   - Submit for monitoring

4. **Ongoing Compliance**
   - Monitor Prometheus dashboard for offset/jitter
   - Ensure uptime > 99%
   - Respond to pool.ntp.org scoring

## 📝 Operational Runbooks

### Daily Checks

```bash
# K3s cluster health
kubectl get nodes
kubectl top nodes

# NTP server status
kubectl -n ntp-server logs -l app=ntp-server --tail=50

# Cost status
./scripts/cost_monitoring.sh check

# Monitoring stack
kubectl -n monitoring get pods
```

### Scaling Up

During high traffic:

```bash
# Manual HPA adjustment
kubectl -n ntp-server patch hpa ntp-server-hpa \
  -p '{"spec":{"maxReplicas":20}}'

# Check current replicas
kubectl -n ntp-server get hpa
```

### Scaling Down

To save costs:

```bash
# Update HPA
kubectl -n ntp-server patch hpa ntp-server-hpa \
  -p '{"spec":{"maxReplicas":5,"minReplicas":1}}'
```

### Adding Cloud Regions

To extend to additional AWS/GCP regions:

1. Update `terraform/aws/variables.tf` or `terraform/gcp/variables.tf`
2. Add new `resource "aws_instance"` or `resource "google_compute_instance"`
3. Update WireGuard peer configuration
4. Re-run Terraform: `terraform apply`

### Updating K3s Version

```bash
# Update K3s on all nodes
# Edit terraform/variables.tf
k3s_version = "v1.28.0"

# Redeploy
terraform apply

# Verify
kubectl get nodes
```

## 🔐 Security Considerations

### Network Security

- **WireGuard**: Encrypted cross-cloud communication (UDP 51820)
- **NetworkPolicy**: Pod-to-pod traffic restrictions (Calico)
- **Security Groups**: Firewall rules on cloud VPCs
- **Rate Limiting**: Via Calico policies (external tools for advanced DDoS)

### Access Control

- **SSH**: Restricted via security groups (update `allowed_ssh_cidrs`)
- **K3s API**: Protected behind RBAC
- **Monitoring**: No public access (port-forward for local access)

### Data Protection

- **EBS/Disk**: Encrypted at rest
- **WireGuard**: Encrypted in transit
- **State Files**: Stored in encrypted S3/GCS (optional)

### Recommendations

1. **Update `allowed_ssh_cidrs`** to your IP (not `0.0.0.0/0`)
2. **Enable VPC Flow Logs** for audit trails
3. **Rotate K3s token** periodically
4. **Use IAM roles** instead of keys (already configured)
5. **Enable CloudTrail** (AWS) and Cloud Audit Logs (GCP)

## 🐛 Troubleshooting

### K3s Cluster Won't Start

```bash
# SSH to control plane
ssh -i your-key.pem ec2-user@<aws-control-plane-ip>

# Check K3s service
sudo systemctl status k3s

# View logs
sudo journalctl -u k3s -f

# Verify network connectivity
ping $(gcp_agent_ip)
sudo wg show
```

### NTP Pods Not Syncing

```bash
# Check pod logs
kubectl -n ntp-server logs -f deployment/ntp-server

# Verify upstream connectivity
kubectl -n ntp-server exec -it <pod-name> -- ntpq -p

# Check network policies
kubectl -n ntp-server get networkpolicies
```

### High Data Transfer Costs

```bash
# Check inter-cloud traffic
# On control plane: sudo vnstat -h
# GCP: gcloud compute networks flow-logs

# Solutions:
# 1. Use WireGuard more efficiently (already enabled)
# 2. Move GCP node to AWS same region (tradeoff: less HA)
# 3. Use AWS PrivateLink / GCP Private Interconnect (~$2,328/month minimum)
```

### Pods Not Scaling

```bash
# Check Metrics Server
kubectl -n kube-system get pods -l k8s-app=metrics-server

# Check HPA status
kubectl -n ntp-server describe hpa ntp-server-hpa

# View metrics
kubectl top pods -n ntp-server
```

### WireGuard Connection Issues

```bash
# On AWS control plane
sudo wg show
sudo wg set wg0 peer <gcp-public-key> endpoint <gcp-ip>:51820

# On GCP agent
sudo wg show
sudo wg set wg0 peer <aws-public-key> endpoint <aws-ip>:51820
```

## 📚 File Structure

```
NTP-MC-NLB/
├── terraform/              # Infrastructure as Code
│   ├── main.tf            # Root configuration
│   ├── variables.tf       # Root variables
│   ├── terraform.tfvars.example
│   ├── aws/               # AWS-specific config
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── vpc_module.tf
│   │   └── user_data/
│   ├── gcp/               # GCP-specific config
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── user_data/
│   └── wireguard/         # WireGuard VPN config
│       ├── main.tf
│       └── variables.tf
├── kubernetes/            # K8s manifests
│   ├── ntp/              # NTP server deployment
│   │   └── deployment.yaml
│   ├── autoscaling/      # HPA configuration
│   │   └── hpa.yaml
│   ├── network-policies/ # Security policies
│   │   └── policies.yaml
│   └── monitoring/       # Prometheus + Grafana
│       ├── prometheus.yaml
│       └── grafana.yaml
├── ansible/              # Configuration management
│   ├── k3s_cluster_setup.yml
│   └── inventory.ini
├── scripts/              # Automation
│   ├── emergency_shutdown.sh
│   ├── cost_monitoring.sh
│   ├── instance_scheduler.sh
│   └── aws_cost_filter.json
├── docs/                 # Documentation (this file)
│   └── ARCHITECTURE.md
└── logs/                 # Runtime logs
    ├── cost_monitoring.log
    └── scheduler.log
```

## 📖 Additional Resources

- [K3s Documentation](https://docs.k3s.io)
- [Calico Networking](https://www.projectcalico.org)
- [NTP Pool Project](https://www.pool.ntp.org)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [Terraform GCP Provider](https://registry.terraform.io/providers/hashicorp/google/latest)
- [pool.ntp.org Registration Guide](https://manage.ntppool.org)

## 🤝 Contributing

Improvements welcome:
- Additional cloud regions (Linode, DigitalOcean)
- Terraform state backend configuration
- Additional monitoring dashboards
- DDoS mitigation enhancements
- Cost optimization strategies

## 📄 License

This project is provided as-is for educational and portfolio purposes.

---

**Last Updated:** January 2026
**Terraform Version:** 1.0+
**K3s Version:** v1.27.7+
