#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ALB_NAME="${ALB_NAME:-capstone-app-alb}"
TG_NAME="${TG_NAME:-capstone-app-targets}"
ASG_NAME="${ASG_NAME:-capstone-app-asg}"
VPC_ID="$(get_vpc_id)"
ALB_SG_ID="$(get_security_group_id "${ALB_SG_NAME:-alb-sg}" "$VPC_ID")"

# ALB must live in public subnets so end users can reach it.
# AWS requires at most one subnet per availability zone for a single ALB.
ALB_SUBNET_IDS=""
declare -A seen_az=()
while read -r az_name subnet_id; do
  if [[ -z "$az_name" || -z "$subnet_id" ]]; then
    continue
  fi
  if [[ -n "${seen_az[$az_name]:-}" ]]; then
    continue
  fi
  seen_az[$az_name]=1
  ALB_SUBNET_IDS="${ALB_SUBNET_IDS:+$ALB_SUBNET_IDS }$subnet_id"
done < <(aws ec2 describe-subnets --region "$AWS_REGION" \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=map-public-ip-on-launch,Values=true" \
  --query 'Subnets[*].{AZ:AvailabilityZone,SubnetId:SubnetId}' --output text)

if [[ -z "$ALB_SUBNET_IDS" ]]; then
  ALB_SUBNET_IDS=""
  declare -A seen_az=()
  while read -r az_name subnet_id; do
    if [[ -z "$az_name" || -z "$subnet_id" ]]; then
      continue
    fi
    if [[ -n "${seen_az[$az_name]:-}" ]]; then
      continue
    fi
    seen_az[$az_name]=1
    ALB_SUBNET_IDS="${ALB_SUBNET_IDS:+$ALB_SUBNET_IDS }$subnet_id"
  done < <(aws ec2 describe-subnets --region "$AWS_REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'Subnets[*].{AZ:AvailabilityZone,SubnetId:SubnetId}' --output text)
fi

EXISTING_ALB_ARN="$(aws elbv2 describe-load-balancers --region "$AWS_REGION" --names "$ALB_NAME" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || true)"

if [[ -n "$EXISTING_ALB_ARN" && "$EXISTING_ALB_ARN" != "None" ]]; then
  echo "ALB '${ALB_NAME}' already exists."
else
  echo "Creating ALB '${ALB_NAME}'..."
  EXISTING_ALB_ARN="$(aws elbv2 create-load-balancer \
    --region "$AWS_REGION" \
    --name "$ALB_NAME" \
    --subnets $ALB_SUBNET_IDS \
    --security-groups "$ALB_SG_ID" \
    --scheme internet-facing \
    --type application \
    --tags Key=Name,Value="$ALB_NAME" Key=project,Value="${COMMON_TAG_VALUE:-capstone-project}" \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text)"
fi

EXISTING_TG_ARN="$(aws elbv2 describe-target-groups --region "$AWS_REGION" --names "$TG_NAME" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || true)"

if [[ -n "$EXISTING_TG_ARN" && "$EXISTING_TG_ARN" != "None" ]]; then
  echo "Target group '${TG_NAME}' already exists."
else
  echo "Creating target group '${TG_NAME}'..."
  EXISTING_TG_ARN="$(aws elbv2 create-target-group \
    --region "$AWS_REGION" \
    --name "$TG_NAME" \
    --protocol HTTP \
    --port 8080 \
    --vpc-id "$VPC_ID" \
    --target-type instance \
    --health-check-path /actuator/health \
    --health-check-interval-seconds 30 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 3 \
    --tags Key=Name,Value="$TG_NAME" Key=project,Value="${COMMON_TAG_VALUE:-capstone-project}" \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)"
fi

if aws elbv2 describe-listeners --region "$AWS_REGION" --load-balancer-arn "$EXISTING_ALB_ARN" --query 'Listeners[?Port==`80`].ListenerArn' --output text | grep -q 'arn:'; then
  echo "Listener on port 80 already exists."
else
  aws elbv2 create-listener \
    --region "$AWS_REGION" \
    --load-balancer-arn "$EXISTING_ALB_ARN" \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn="$EXISTING_TG_ARN" >/dev/null
fi

# If an Auto Scaling Group already exists, attach the target group to it.
if aws autoscaling describe-auto-scaling-groups --region "$AWS_REGION" --auto-scaling-group-names "$ASG_NAME" >/dev/null 2>&1; then
  aws autoscaling attach-load-balancer-target-groups \
    --region "$AWS_REGION" \
    --auto-scaling-group-name "$ASG_NAME" \
    --target-group-arns "$EXISTING_TG_ARN" >/dev/null || true
fi

ALB_DNS="$(aws elbv2 describe-load-balancers --region "$AWS_REGION" --names "$ALB_NAME" --query 'LoadBalancers[0].DNSName' --output text)"
printf 'ALB DNS Name: %s\n' "$ALB_DNS"
printf 'App target group: %s\n' "$EXISTING_TG_ARN"
printf 'App traffic from end users is routed to the ASG via the ALB.\n'
