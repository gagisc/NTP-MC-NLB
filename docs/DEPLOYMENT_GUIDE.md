# DEPLOYMENT_GUIDE.md - Step-by-Step Deployment

## Prerequisites Checklist

### AWS Account
- [ ] AWS account created and verified
- [ ] Free tier eligibility confirmed (12 months)
- [ ] AWS CLI installed: `aws --version`
- [ ] AWS credentials configured: `aws configure`
  - Region: `us-east-1`
  - Access Key ID: `YOUR_KEY`
  - Secret Access Key: `YOUR_SECRET`
- [ ] EC2 key pair created and downloaded
  ```bash
  aws ec2 create-key-pair --key-name ntp-mc-nlb \
    --query 'KeyMaterial' --output text > ntp-mc-nlb.pem
  chmod 600 ntp-mc-nlb.pem
  ```

### GCP Account
- [ ] GCP project created
- [ ] Free tier/trial activated
- [ ] Billing account configured
- [ ] gcloud CLI installed: `gcloud --version`
- [ ] gcloud initialized: `gcloud init`
- [ ] APIs enabled:
  ```bash
  gcloud services enable compute.googleapis.com
  gcloud services enable cloudresourcemanager.googleapis.com
  gcloud services enable monitoring.googleapis.com
  ```
- [ ] Service account created:
  ```bash
  gcloud iam service-accounts create ntp-server \
    --display-name="NTP Server Service Account"
  gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
    --member=serviceAccount:ntp-server@YOUR_PROJECT_ID.iam.gserviceaccount.com \
    --role=roles/compute.admin
  ```

### Local Machine
- [ ] Terraform >= 1.0: `terraform --version`
- [ ] kubectl >= 1.27: `kubectl version --client`
- [ ] Ansible >= 2.10: `ansible --version`
- [ ] Git installed (for versioning)
- [ ] SSH client available
- [ ] Text editor for configuration files

## Step 1: Configuration

### 1.1 Clone Repository
```bash
cd ~/projects  # or your preferred location
git clone <your-ntp-mc-nlb-repo>
cd NTP-MC-NLB
```

### 1.2 Gather Information

Before deployment, collect the following information:

**AWS:**
```bash
# Find your account ID
aws sts get-caller-identity --query Account --output text
# Output: 123456789012

# List available regions
aws ec2 describe-regions --query 'Regions[].RegionName'
```

**GCP:**
```bash
# Get project ID
gcloud config get-value project
# Output: your-project-id

# Get project number
gcloud projects describe $(gcloud config get-value project) \
  --format='value(projectNumber)'
# Output: 123456789012

# Find billing account
gcloud billing accounts list --format='value(name)'
# Output: 0123456-789ABCDE-FGHIJK
```

### 1.3 Create terraform.tfvars

```bash
cd terraform

# Copy template
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars  # or your preferred editor
```

**Example terraform.tfvars:**
```hcl
# AWS Configuration
aws_region       = "us-east-1"
aws_instance_type = "t2.micro"
aws_agent_count  = 1
aws_vpc_cidr     = "10.0.0.0/16"
aws_budget_limit = "5"

# GCP Configuration
gcp_project_id         = "my-ntp-project"
gcp_project_number     = "123456789012"
gcp_region             = "us-central1"
gcp_zone               = "us-central1-a"
gcp_instance_type      = "e2-micro"
gcp_subnet_cidr        = "10.1.0.0/16"
gcp_billing_account_id = "0123456-789ABCDE-FGHIJK"
gcp_budget_limit       = 5

# Environment
environment        = "production"
allowed_ssh_cidrs  = ["203.0.113.0/32"]  # YOUR IP HERE!

# Alerts
alert_email_addresses = ["your-email@example.com"]
gcp_notification_channels = []  # Will configure later

# K3s
k3s_token = "g7mX5kL2nP9qR3wT6yU8vZ1aB4cD7eF0gH3iJ6kL9m"  # Run: openssl rand -base64 32
k3s_version = "v1.27.7"
```

**Generate K3s Token:**
```bash
openssl rand -base64 32
# Copy output to terraform.tfvars k3s_token field
```

### 1.4 Update Ansible Inventory

```bash
cd ../ansible

# Edit inventory.ini
nano inventory.ini
```

**After you know the IPs from terraform output**, update:
```ini
[k3s_control_plane]
aws-k3s-cp-1 ansible_host=3.95.123.45 ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/ntp-mc-nlb.pem

[k3s_agents]
aws-k3s-agent-1 ansible_host=3.95.123.46 ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/ntp-mc-nlb.pem
gcp-k3s-agent-1 ansible_host=35.223.123.47 ansible_user=debian ansible_ssh_private_key_file=~/.ssh/ntp-mc-nlb.pem

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

## Step 2: Infrastructure Deployment

### 2.1 Validate Terraform Configuration

```bash
cd terraform

# Check for syntax errors
terraform validate

# Expected output:
# Success! The configuration is valid.
```

### 2.2 Plan Deployment

```bash
# Generate execution plan (no changes yet)
terraform plan -out=tfplan

# Review the plan output:
# - 15-20 resources will be created (AWS instances, GCP instances, etc.)
# - Check for any errors or unexpected changes
```

### 2.3 Apply Infrastructure

```bash
# Deploy all resources
terraform apply tfplan

# This will:
# 1. Generate WireGuard keys
# 2. Create AWS VPC, security groups, EC2 instances
# 3. Create GCP VPC, firewall rules, compute instances
# 4. Allocate Elastic IPs (AWS)
# 5. Configure instances with K3s + WireGuard

# Expected time: 10-15 minutes
# Watch the output for any errors

# At the end, Terraform will output:
# aws_control_plane_ip = "3.95.123.45"
# aws_agent_ips = ["3.95.123.46"]
# gcp_agent_ip = "35.223.123.47"
# k3s_cluster_info = { control_plane_ip = "3.95.123.45", ... }
# wireguard_config = { aws_cp_ip = "192.168.10.1", ... }
```

### 2.4 Save Outputs

```bash
# Save important outputs
terraform output > deployment_outputs.txt

# Extract kubeconfig from AWS control plane
ssh -i ~/.ssh/ntp-mc-nlb.pem ec2-user@3.95.123.45 \
  "sudo cat /etc/rancher/k3s/k3s.yaml" > kubeconfig

# Fix kubeconfig server IP
sed -i 's/127.0.0.1/3.95.123.45/g' kubeconfig
sed -i 's/localhost/3.95.123.45/g' kubeconfig

# Test kubeconfig
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes
# Should show AWS and GCP nodes as Ready
```

## Step 3: Kubernetes Configuration

### 3.1 Verify K3s Cluster

```bash
export KUBECONFIG=$(pwd)/terraform/kubeconfig

# Check nodes
kubectl get nodes -o wide
# Expected:
# NAME                         STATUS   ROLES                  AGE     IP
# aws-k3s-cp                   Ready    control-plane,master   5m      10.0.0.10
# aws-k3s-agent-1              Ready    <none>                 4m      10.0.0.11
# gcp-k3s-agent-1              Ready    <none>                 3m      10.1.0.10

# Check system pods
kubectl get pods -A
# Should see: coredns, local-path-provisioner, metrics-server, etc.

# Check Calico networking
kubectl -n tigera-operator get pods
# Calico controller should be running

# Check DNS
kubectl run -it --rm debug --image=busybox:1.28 --restart=Never -- \
  nslookup kubernetes.default
# Should resolve successfully
```

### 3.2 Deploy Monitoring Stack

```bash
# Create monitoring manifests (from kubernetes/monitoring/)
kubectl apply -f kubernetes/monitoring/prometheus.yaml
kubectl apply -f kubernetes/monitoring/grafana.yaml

# Wait for deployments to be ready
kubectl -n monitoring wait --for=condition=available \
  --timeout=300s deployment/prometheus
kubectl -n monitoring wait --for=condition=available \
  --timeout=300s deployment/grafana

# Check services
kubectl -n monitoring get svc
```

### 3.3 Deploy NTP Server

```bash
# Create NTP namespace and deployment
kubectl apply -f kubernetes/ntp/deployment.yaml

# Wait for deployment
kubectl -n ntp-server wait --for=condition=available \
  --timeout=300s deployment/ntp-server

# Verify NTP pods
kubectl -n ntp-server get pods
# Should see 2 pods in Running state

# Check NTP service
kubectl -n ntp-server get svc
# Should show EXTERNAL-IP for LoadBalancer service
```

### 3.4 Deploy Auto-Scaling

```bash
# Apply HPA and VPA
kubectl apply -f kubernetes/autoscaling/hpa.yaml

# Verify HPA
kubectl -n ntp-server get hpa
# Should show: REFERENCE, TARGETS, MINPODS, MAXPODS, REPLICAS

# Check HPA status
kubectl -n ntp-server describe hpa ntp-server-hpa
```

### 3.5 Deploy Network Policies

```bash
# Apply network security policies
kubectl apply -f kubernetes/network-policies/policies.yaml

# Verify policies
kubectl -n ntp-server get networkpolicies
```

## Step 4: Testing & Verification

### 4.1 Verify NTP Service

```bash
# Get NTP service external IP
NTP_IP=$(kubectl -n ntp-server get svc ntp-server \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "NTP Service IP: $NTP_IP"

# Test NTP locally
ntpdate -q $NTP_IP
# Expected: "adjust time server 3.95.123.45 offset 0.012345 sec"

# Check NTP status from pod
kubectl -n ntp-server exec -it $(kubectl -n ntp-server get pod -o name | head -1) -- \
  ntpq -p
# Should show upstream servers and sync status
```

### 4.2 Access Monitoring Dashboards

```bash
# Port-forward Grafana
kubectl -n monitoring port-forward svc/grafana 3000:3000 &
# Visit http://localhost:3000
# Username: admin
# Password: admin

# Port-forward Prometheus
kubectl -n monitoring port-forward svc/prometheus 9090:9090 &
# Visit http://localhost:9090

# View metrics
# - Count NTP requests: sum(rate(ntp_requests_total[5m]))
# - NTP latency: histogram_quantile(0.95, ntp_request_duration_seconds)
```

### 4.3 Check Cross-Cloud Connectivity

```bash
# SSH to AWS control plane
ssh -i ~/.ssh/ntp-mc-nlb.pem ec2-user@3.95.123.45

# Check WireGuard tunnel
sudo wg show
# Should show:
# - Interface: wg0
# - Private key: (hidden)
# - Public key: xxxxx
# - Peers: 2 (GCP agent + AWS agent)
# - Latest handshake: (recent)

# Ping GCP node through WireGuard
ping 192.168.10.2
# Should respond

# Check pod connectivity
kubectl exec -it <ntp-pod-name> -n ntp-server -- ping 192.168.10.2
```

### 4.4 Load Testing (Optional)

```bash
# Install stress testing tool
sudo yum install -y httperf  # AWS

# Generate NTP queries
for i in {1..100}; do
  ntpdate -q $NTP_IP &
done
wait

# Monitor pod scaling
watch kubectl -n ntp-server get hpa
# Should see replicas increasing as load increases

# Check metrics
kubectl top pods -n ntp-server
# Monitor CPU/Memory utilization
```

## Step 5: Cost Monitoring Setup

### 5.1 AWS Budget Alerts

```bash
# Verify budget was created (configured in Terraform)
aws budgets describe-budgets --account-id $(aws sts get-caller-identity --query Account --output text)

# Should see:
# - Budget Name: NTP-MC-NLB-Free-Tier-Limit
# - Limit: $5 USD
# - Notifications at 50%, 80%, 100%
```

### 5.2 GCP Budget Alerts

```bash
# Configure notification channels
gcloud alpha billing budgets list --billing-account=YOUR_BILLING_ACCOUNT

# Create notification channel (if not done)
gcloud alpha billing budgets update projects/YOUR_PROJECT_ID/budgets/1234567890 \
  --display-name="NTP Budget Alert" \
  --budget-amount=5.00 \
  --threshold-rule=percent=80 \
  --threshold-rule=percent=100
```

### 5.3 Start Cost Monitoring

```bash
# Make scripts executable
chmod +x scripts/cost_monitoring.sh
chmod +x scripts/instance_scheduler.sh
chmod +x scripts/emergency_shutdown.sh

# Run cost check
./scripts/cost_monitoring.sh check

# Start continuous monitoring (runs in background)
nohup ./scripts/cost_monitoring.sh monitor > logs/cost_monitor.log 2>&1 &

# Setup cron job for daily scheduling
(crontab -l 2>/dev/null; echo "0 0 * * * /path/to/NTP-MC-NLB/scripts/instance_scheduler.sh all YOUR_GCP_PROJECT") | crontab -
```

## Step 6: NTP Pool Registration

### 6.1 Pre-Registration Testing (48+ hours)

```bash
# Monitor NTP metrics for 48 hours before registration
watch kubectl -n ntp-server logs -l app=ntp-server -f

# Verify metrics via Prometheus
# - Stratum: should be 2
# - Offset: should be < 10ms
# - Jitter: should be < 50ms
# - Uptime: should be > 95%
```

### 6.2 Register with pool.ntp.org

1. Visit: https://manage.ntppool.org/
2. Click "Add Server"
3. Enter:
   - **IPv4 Address**: (from `kubectl get svc ntp-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}'`)
   - **IPv6 Address**: (if available)
   - **Hostname**: (optional, e.g., ntp.example.com)
   - **Country**: Your location

4. Submit for monitoring

### 6.3 Monitor Pool Status

```bash
# Check pool.ntp.org dashboard
# Wait for "Active" status (usually within 24 hours)

# Monitor via CLI
ntpdate -q <your-ntp-ip>
# Should show successful sync

# Check scoring
# Visit https://www.pool.ntp.org/ and search your IP
# Look for green uptime percentage
```

## Step 7: Post-Deployment

### 7.1 Documentation

```bash
# Save deployment information
cat > deployment_info.txt << EOF
Deployment Date: $(date)
AWS Control Plane: $AWS_CP_IP
AWS Agents: $AWS_AGENT_IPS
GCP Agent: $GCP_AGENT_IP
NTP Service IP: $NTP_IP
Pool.ntp.org Status: Not yet registered
Kubeconfig: $(pwd)/kubeconfig
EOF
```

### 7.2 Regular Backups

```bash
# Backup Terraform state
cp terraform/terraform.tfstate backups/terraform.tfstate.$(date +%Y%m%d-%H%M%S)

# Backup kubeconfig
cp kubeconfig backups/kubeconfig.$(date +%Y%m%d-%H%M%S)

# Export K8s manifests
kubectl get all -A -o yaml > backups/kubernetes-all.$(date +%Y%m%d).yaml
```

### 7.3 Scheduled Maintenance

```bash
# Monthly tasks
- [ ] Review cost report
- [ ] Check for security updates
- [ ] Update K3s version if needed
- [ ] Review logs for errors
- [ ] Test disaster recovery
- [ ] Update NTP pool status

# Quarterly tasks
- [ ] Full infrastructure audit
- [ ] Review architecture for optimization
- [ ] Update documentation
- [ ] Plan for paid tier (if needed)
```

## Troubleshooting Quick Reference

### Nodes Not Ready
```bash
kubectl describe node <node-name>
# Check Events and Conditions sections
kubectl logs -n kube-system -l k8s-app=kubelet
```

### NTP Pods Not Starting
```bash
kubectl -n ntp-server describe pod <pod-name>
kubectl -n ntp-server logs <pod-name>
# Check for resource constraints or image pull errors
```

### High Latency Between Clouds
```bash
# Check WireGuard tunnel
ssh -i ~/.ssh/ntp-mc-nlb.pem ec2-user@<aws-cp-ip> sudo wg
# Verify peer endpoint and handshake is recent

# Test cross-cloud latency
kubectl exec -it <pod> -n ntp-server -- ping 192.168.10.2
```

### Cost Spike
```bash
./scripts/cost_monitoring.sh report
aws ce get-cost-and-usage --time-period Start=2026-01-01,End=2026-01-31 \
  --granularity DAILY --metrics "BlendedCost" --group-by Type=DIMENSION,Key=SERVICE
```

---

**Version:** 1.0
**Last Updated:** January 2026
**Expected Deployment Time:** 15-30 minutes (plus 48 hours for pool.ntp.org testing)
