#!/bin/bash
# Instance Scheduler Script
# Rotates instances on/off to maintain free tier eligibility and minimize costs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/../logs/scheduler.log"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# AWS Instance Scheduling
schedule_aws_instances() {
    local region="us-east-1"
    local tag_key="CostRotation"
    local tag_value="enabled"
    
    # Get day of week (0=Sunday, 1=Monday, etc.)
    local day_of_week=$(date +%u)
    
    # Schedule: Run AWS M-W (weekdays 1-3), rotate to GCP Th-Su (4-7)
    if [ "$day_of_week" -le 3 ]; then
        log "Monday-Wednesday: Starting AWS instances"
        
        # Start control plane and agents
        aws ec2 start-instances \
            --instance-ids $(aws ec2 describe-instances \
                --region "$region" \
                --filters "Name=tag:$tag_key,Values=$tag_value" "Name=instance-state-name,Values=stopped" \
                --query 'Reservations[*].Instances[*].InstanceId' \
                --output text) \
            --region "$region" 2>/dev/null || log "No instances to start"
        
    else
        log "Thursday-Sunday: Stopping AWS instances to save costs"
        
        # Stop all agents (keep control plane for metadata)
        aws ec2 stop-instances \
            --instance-ids $(aws ec2 describe-instances \
                --region "$region" \
                --filters "Name=tag:$tag_key,Values=$tag_value" "Name=instance-state-name,Values=running" "Name=tag:Role,Values=agent" \
                --query 'Reservations[*].Instances[*].InstanceId' \
                --output text) \
            --region "$region" 2>/dev/null || log "No agent instances to stop"
    fi
}

# GCP Instance Scheduling
schedule_gcp_instances() {
    local project_id=$1
    local zone="us-central1-a"
    
    local day_of_week=$(date +%u)
    
    if [ "$day_of_week" -ge 4 ]; then
        log "Thursday-Sunday: Starting GCP instances"
        
        gcloud compute instances start \
            --project="$project_id" \
            --zone="$zone" \
            --filter="labels.cost-rotation:enabled" \
            --no-user-output-enabled || log "No GCP instances to start"
        
    else
        log "Monday-Wednesday: Stopping GCP instances to save costs"
        
        gcloud compute instances stop \
            --project="$project_id" \
            --zone="$zone" \
            --filter="labels.cost-rotation:enabled" \
            --async \
            --no-user-output-enabled || log "No GCP instances to stop"
    fi
}

# Scale down K3s cluster during off-hours
scale_k3s_cluster() {
    local hour=$(date +%H)
    
    # Scale down 2am-6am UTC
    if [ "$hour" -ge 2 ] && [ "$hour" -le 6 ]; then
        log "Off-peak hours: Scaling down K3s cluster"
        
        kubectl set env deployment/ntp-server \
            -n ntp-server \
            MIN_REPLICAS=1 \
            MAX_REPLICAS=3 \
            || log "Could not scale cluster"
    else
        log "Peak hours: Scaling up K3s cluster"
        
        kubectl set env deployment/ntp-server \
            -n ntp-server \
            MIN_REPLICAS=2 \
            MAX_REPLICAS=10 \
            || log "Could not scale cluster"
    fi
}

# Main execution
case "${1:-all}" in
    aws)
        schedule_aws_instances
        ;;
    gcp)
        schedule_gcp_instances "${2:-your-gcp-project}"
        ;;
    k3s)
        scale_k3s_cluster
        ;;
    all)
        schedule_aws_instances
        schedule_gcp_instances "${2:-your-gcp-project}"
        scale_k3s_cluster
        ;;
    *)
        echo "Usage: $0 {aws|gcp|k3s|all} [gcp-project-id]"
        exit 1
        ;;
esac

log "Scheduling complete"
