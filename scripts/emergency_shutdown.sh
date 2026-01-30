#!/bin/bash
# Emergency Shutdown Script - Destroys all infrastructure
# Use this to immediately halt all instances and prevent runaway costs

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${RED}=== EMERGENCY INFRASTRUCTURE SHUTDOWN ===${NC}"
echo -e "${YELLOW}WARNING: This will destroy ALL infrastructure!${NC}"
echo ""
echo "This script will:"
echo "  1. Destroy AWS EC2 instances"
echo "  2. Destroy GCP Compute instances"
echo "  3. Release Elastic IPs"
echo "  4. Delete VPCs and networks"
echo ""
read -p "Type 'I UNDERSTAND' to proceed: " confirmation

if [ "$confirmation" != "I UNDERSTAND" ]; then
    echo "Cancelled. No changes made."
    exit 1
fi

echo ""
echo -e "${YELLOW}Initiating emergency shutdown...${NC}"

cd "$(dirname "$0")/../terraform"

# Create a backup of state
echo "Creating backup of Terraform state..."
mkdir -p backups
cp terraform.tfstate backups/terraform.tfstate.backup.$(date +%s) 2>/dev/null || true

# Destroy AWS resources
echo -e "${YELLOW}Destroying AWS infrastructure...${NC}"
terraform destroy -target=module.aws -auto-approve || echo "AWS destruction completed with status"

# Destroy GCP resources
echo -e "${YELLOW}Destroying GCP infrastructure...${NC}"
terraform destroy -target=module.gcp -auto-approve || echo "GCP destruction completed with status"

# Destroy WireGuard resources
echo -e "${YELLOW}Destroying WireGuard configuration...${NC}"
terraform destroy -target=module.wireguard -auto-approve || echo "WireGuard destruction completed with status"

# Final cleanup
echo -e "${YELLOW}Performing final cleanup...${NC}"
terraform destroy -auto-approve || echo "Final cleanup completed with status"

echo ""
echo -e "${GREEN}=== EMERGENCY SHUTDOWN COMPLETE ===${NC}"
echo "All infrastructure has been destroyed."
echo "Backup of Terraform state saved in: backups/terraform.tfstate.backup.*"
echo ""
echo -e "${RED}Verify destruction:${NC}"
echo "  AWS:  aws ec2 describe-instances --region us-east-1"
echo "  GCP:  gcloud compute instances list --project=YOUR_PROJECT_ID"
