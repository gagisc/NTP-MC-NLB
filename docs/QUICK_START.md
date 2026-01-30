# QUICK_START.md - 5-Minute Setup Summary

## TL;DR - Deploy NTP Server in 3 Commands

```bash
# 1. Configure
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit: gcp_project_id, k3s_token, alert_email_addresses

# 2. Deploy
terraform init
terraform apply

# 3. Verify
export KUBECONFIG=$(cd .. && pwd)/kubeconfig
kubectl -n ntp-server get svc
```

## What You Get

✅ **Multi-Cloud K3s Cluster**
- AWS (t2.micro) control plane + agents
- GCP (e2-micro) agents
- Connected via WireGuard VPN

✅ **NTP Stratum 2 Server**
- RFC 5905 compliant
- Auto-scaling (2-10 pods)
- Ready for pool.ntp.org registration

✅ **Monitoring & Observability**
- Prometheus metrics collection
- Grafana dashboards
- Cost tracking & alerts

✅ **Cost Optimization**
- Stays in free tier during trial
- Rotation scheduling (Mon-Wed AWS, Thu-Sun GCP)
- Emergency shutdown script

✅ **Infrastructure as Code**
- Terraform for cloud resources
- Ansible for configuration
- Kubernetes manifests for apps
- 100% reproducible

## Prerequisites (5 minutes)

```bash
# Check tools installed
terraform --version      # >= 1.0
kubectl version --client # >= 1.27
gcloud --version         # GCP SDK
aws --version            # AWS CLI >= 2.0

# Configure AWS credentials
aws configure
# Region: us-east-1
# Access Key: YOUR_KEY
# Secret: YOUR_SECRET

# Initialize GCP
gcloud init
gcloud auth application-default login
```

## Configuration (5 minutes)

### 1. Gather Information

**AWS Account ID:**
```bash
aws sts get-caller-identity --query Account --output text
# Copy: 123456789012
```

**GCP Project Info:**
```bash
gcloud config get-value project
# Copy: your-project-id

gcloud projects describe $(gcloud config get-value project) --format='value(projectNumber)'
# Copy: 123456789012

gcloud billing accounts list --format='value(name)'
# Copy: 0123456-789ABCDE-FGHIJK
```

**K3s Token:**
```bash
openssl rand -base64 32
# Copy: generated-token-here
```

### 2. Create terraform.tfvars

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

**Replace with your values:**
```hcl
gcp_project_id         = "your-project-id"
gcp_project_number     = "123456789012"
gcp_billing_account_id = "0123456-789ABCDE-FGHIJK"
alert_email_addresses  = ["your-email@example.com"]
allowed_ssh_cidrs      = ["YOUR_IP/32"]  # Your public IP
k3s_token             = "your-generated-token"
```

## Deployment (10 minutes)

```bash
# Validate configuration
terraform validate

# Plan deployment
terraform plan -out=tfplan

# Deploy infrastructure
terraform apply tfplan

# Wait 10-15 minutes...
# Watch the output for:
# - aws_control_plane_ip
# - gcp_agent_ip
# - ntp service deployment

# Save outputs
terraform output > ../deployment_outputs.txt
```

## Post-Deployment (5 minutes)

```bash
# Extract kubeconfig
ssh -i ~/.ssh/ntp-mc-nlb.pem ec2-user@<aws-control-plane-ip> \
  "sudo cat /etc/rancher/k3s/k3s.yaml" > ../kubeconfig
sed -i 's/127.0.0.1/<aws-control-plane-ip>/g' ../kubeconfig

# Verify cluster
export KUBECONFIG=$(pwd)/../kubeconfig
kubectl get nodes

# Deploy applications
cd ../kubernetes
kubectl apply -f ntp/deployment.yaml
kubectl apply -f monitoring/prometheus.yaml
kubectl apply -f monitoring/grafana.yaml
kubectl apply -f autoscaling/hpa.yaml
kubectl apply -f network-policies/policies.yaml

# Verify NTP service
kubectl -n ntp-server get svc
# Copy EXTERNAL-IP

# Test NTP
ntpdate -q <EXTERNAL-IP>
```

## Access Services

### Grafana (Monitoring Dashboard)
```bash
kubectl -n monitoring port-forward svc/grafana 3000:3000
# http://localhost:3000
# Username: admin
# Password: admin
```

### Prometheus (Metrics)
```bash
kubectl -n monitoring port-forward svc/prometheus 9090:9090
# http://localhost:9090
```

### K3s API (Direct Access)
```bash
kubectl get nodes -o wide
kubectl -n ntp-server get pods
kubectl -n ntp-server logs -l app=ntp-server
```

## Monitoring Costs

```bash
# Check current spend
cd scripts
./cost_monitoring.sh check

# Start continuous monitoring
./cost_monitoring.sh monitor &

# View logs
tail -f ../logs/cost_monitoring.log
```

## Emergency Procedures

### Shutdown Everything
```bash
cd terraform
../scripts/emergency_shutdown.sh
# Type: I UNDERSTAND
```

### Scale Cluster
```bash
# Scale NTP pods up
kubectl -n ntp-server patch hpa ntp-server-hpa \
  -p '{"spec":{"maxReplicas":20}}'

# Scale down
kubectl -n ntp-server patch hpa ntp-server-hpa \
  -p '{"spec":{"maxReplicas":5}}'
```

### Check Cluster Health
```bash
kubectl get nodes -o wide
kubectl top nodes
kubectl -n ntp-server get pods
kubectl -n monitoring get pods
```

## Next Steps

1. **Register with pool.ntp.org** (after 48 hours testing)
   - https://manage.ntppool.org/
   - Submit server IP
   - Wait for monitoring

2. **Configure backup (optional)**
   - Enable S3/GCS remote state in Terraform
   - Setup automated backups

3. **Customize monitoring**
   - Import Grafana dashboards
   - Configure alerting rules
   - Integrate with your monitoring stack

4. **Production hardening**
   - Enable VPC Flow Logs
   - Setup CloudTrail/Audit Logs
   - Implement DDoS protection

## Troubleshooting

### Terraform Won't Init
```bash
# Clear cache and retry
rm -rf .terraform
terraform init
```

### Nodes Not Coming Up
```bash
# Check AWS/GCP console for launch errors
# Check system logs
ssh -i ~/.ssh/ntp-mc-nlb.pem ec2-user@<ip> sudo journalctl -u k3s -f
```

### NTP Pods Stuck
```bash
# Check resource availability
kubectl describe nodes
# Check pod events
kubectl -n ntp-server describe pod <pod-name>
```

### Cost Exceeded
```bash
# Immediate shutdown
terraform destroy -auto-approve
# Or use script
../scripts/emergency_shutdown.sh
```

## Cost Estimate

| Phase | AWS | GCP | Total |
|-------|-----|-----|-------|
| Free Tier (12 months) | FREE | FREE | **FREE** |
| After Trial | $11.47 | $18.17 | **~$30/month** |
| With Load Balancer | +$4.98 | +$18.80 | **~$74/month** |
| With Cross-Cloud Data | - | - | **+$21/month** |

*Costs vary by region and data transfer patterns*

## File Structure

```
NTP-MC-NLB/
├── terraform/          # Infrastructure (Deploy first)
│   ├── main.tf
│   ├── variables.tf
│   └── terraform.tfvars.example (copy to terraform.tfvars)
├── kubernetes/         # Applications (Deploy second)
│   ├── ntp/
│   ├── monitoring/
│   ├── autoscaling/
│   └── network-policies/
├── ansible/           # Configuration management
├── scripts/           # Automation & monitoring
└── docs/             # Documentation (you are here!)
```

## Important Links

- [Terraform Docs](https://www.terraform.io/docs)
- [K3s Docs](https://docs.k3s.io)
- [pool.ntp.org](https://www.pool.ntp.org)
- [AWS Free Tier](https://aws.amazon.com/free)
- [GCP Free Tier](https://cloud.google.com/free)

## Support

For detailed information, see:
- [README.md](README.md) - Full documentation
- [ARCHITECTURE.md](ARCHITECTURE.md) - System design
- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) - Step-by-step guide

---

**Total Setup Time:** ~30 minutes (first time)
**Ongoing Maintenance:** ~5 minutes/week
**Interview Talking Points:** K3s, Terraform, WireGuard, cross-cloud networking, cost optimization, Kubernetes scaling
