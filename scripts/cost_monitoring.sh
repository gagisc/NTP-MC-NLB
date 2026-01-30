#!/bin/bash
# Cost Monitoring and Alert Script
# Monitors AWS and GCP costs and triggers alerts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
ALERT_EMAIL="${ALERT_EMAIL:-your-email@example.com}"
AWS_BUDGET_LIMIT=${AWS_BUDGET_LIMIT:-5}
GCP_BUDGET_LIMIT=${GCP_BUDGET_LIMIT:-5}
ALERT_THRESHOLD_PERCENT=${ALERT_THRESHOLD_PERCENT:-80}
LOG_FILE="${PROJECT_ROOT}/logs/cost_monitoring.log"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

get_aws_costs() {
    # Get AWS current month costs (requires aws-cli configured)
    local today=$(date +%Y-%m-01)
    local end_date=$(date +%Y-%m-%d)
    
    aws ce get-cost-and-usage \
        --time-period Start="$today",End="$end_date" \
        --granularity MONTHLY \
        --metrics "BlendedCost" \
        --filter file://aws_cost_filter.json \
        --query 'ResultsByTime[0].Total.BlendedCost.Amount' \
        --output text 2>/dev/null || echo "0"
}

get_gcp_costs() {
    # Get GCP current month costs (requires gcloud configured)
    local project_id=$1
    
    gcloud billing accounts list --format='value(name)' | head -1 | xargs -I {} \
    gcloud billing projects describe --billing-account {} "$project_id" \
    --format='value(billingAccountName)' 2>/dev/null || echo "0"
}

check_aws_budget() {
    local current_cost=$(get_aws_costs)
    local threshold_amount=$(echo "$AWS_BUDGET_LIMIT * $ALERT_THRESHOLD_PERCENT / 100" | bc)
    
    log "AWS Current Cost: \$$current_cost (Limit: \$$AWS_BUDGET_LIMIT)"
    
    if (( $(echo "$current_cost > $threshold_amount" | bc -l) )); then
        log -e "${RED}WARNING: AWS costs approaching limit!${NC}"
        send_alert "AWS" "$current_cost" "$AWS_BUDGET_LIMIT"
    elif (( $(echo "$current_cost > $AWS_BUDGET_LIMIT" | bc -l) )); then
        log -e "${RED}CRITICAL: AWS costs EXCEEDED limit!${NC}"
        send_critical_alert "AWS" "$current_cost" "$AWS_BUDGET_LIMIT"
    fi
}

check_gcp_budget() {
    local project_id=$1
    local current_cost=$(get_gcp_costs "$project_id")
    local threshold_amount=$(echo "$GCP_BUDGET_LIMIT * $ALERT_THRESHOLD_PERCENT / 100" | bc)
    
    log "GCP Current Cost: \$$current_cost (Limit: \$$GCP_BUDGET_LIMIT)"
    
    if (( $(echo "$current_cost > $threshold_amount" | bc -l) )); then
        log -e "${YELLOW}WARNING: GCP costs approaching limit!${NC}"
        send_alert "GCP" "$current_cost" "$GCP_BUDGET_LIMIT"
    elif (( $(echo "$current_cost > $GCP_BUDGET_LIMIT" | bc -l) )); then
        log -e "${RED}CRITICAL: GCP costs EXCEEDED limit!${NC}"
        send_critical_alert "GCP" "$current_cost" "$GCP_BUDGET_LIMIT"
    fi
}

send_alert() {
    local provider=$1
    local current=$2
    local limit=$3
    local percentage=$(echo "$current / $limit * 100" | bc)
    
    log "Sending alert for $provider (${percentage}% of budget)"
    
    # Send via mail (requires mail utility)
    if command -v mail &> /dev/null; then
        echo "NTP-MC-NLB Cost Alert: $provider has reached ${percentage}% of budget ($current / $limit)" | \
        mail -s "Cost Alert: $provider Budget $percentage% Used" "$ALERT_EMAIL"
    fi
    
    # Log to file for dashboard ingestion
    echo "{\"timestamp\": \"$(date -Iseconds)\", \"provider\": \"$provider\", \"cost\": \"$current\", \"limit\": \"$limit\", \"percentage\": \"$percentage\"}" >> "$LOG_FILE"
}

send_critical_alert() {
    local provider=$1
    local current=$2
    local limit=$3
    
    log -e "${RED}CRITICAL ALERT: $provider costs exceeded!${NC}"
    send_alert "$provider" "$current" "$limit"
    
    # Optionally trigger emergency shutdown
    # read -p "Costs exceeded! Run emergency shutdown? (y/n): " -n 1 -r
    # if [[ $REPLY =~ ^[Yy]$ ]]; then
    #     "$SCRIPT_DIR/emergency_shutdown.sh"
    # fi
}

show_cost_report() {
    log -e "${GREEN}=== Monthly Cost Report ===${NC}"
    log "AWS Budget: \$$AWS_BUDGET_LIMIT"
    log "GCP Budget: \$$GCP_BUDGET_LIMIT"
    log ""
    log "Current AWS Cost: $(get_aws_costs)"
    # log "Current GCP Cost: $(get_gcp_costs $1)"
}

# Main execution
case "${1:-check}" in
    check)
        check_aws_budget
        ;;
    report)
        show_cost_report
        ;;
    monitor)
        while true; do
            log "Running cost check..."
            check_aws_budget
            sleep 3600  # Check every hour
        done
        ;;
    *)
        echo "Usage: $0 {check|report|monitor}"
        echo "  check   - Run one-time cost check"
        echo "  report  - Display cost report"
        echo "  monitor - Continuous monitoring (checks every hour)"
        exit 1
        ;;
esac
