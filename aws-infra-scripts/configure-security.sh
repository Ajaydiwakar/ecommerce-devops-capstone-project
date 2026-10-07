#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

VPC_ID="${VPC_ID:-$(get_vpc_id)}"
MY_IP="${MY_IP:-$(curl -s https://checkip.amazonaws.com 2>/dev/null || curl -s ifconfig.me 2>/dev/null || echo 0.0.0.0)}"
MY_CIDR="${MY_CIDR:-${MY_IP}/32}"

get_or_create_sg() {
  local sg_name="$1"
  local description="$2"
  local vpc_id="$3"
  local sg_id

  sg_id="$(aws ec2 describe-security-groups --region "$AWS_REGION" --filters "Name=vpc-id,Values=${vpc_id}" "Name=group-name,Values=${sg_name}" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)"

  if [[ -z "$sg_id" || "$sg_id" == "None" ]]; then
    echo "Creating security group '${sg_name}' in VPC ${vpc_id}..."
    sg_id="$(aws ec2 create-security-group \
      --region "$AWS_REGION" \
      --group-name "$sg_name" \
      --description "$description" \
      --vpc-id "$vpc_id" \
      --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${sg_name}},{Key=${COMMON_TAG_KEY:-Project},Value=${COMMON_TAG_VALUE:-capstone-project}}]" \
      --query 'GroupId' \
      --output text)"
  fi
  echo "$sg_id"
}

ensure_rule() {
  local group_id="$1"
  local protocol="$2"
  local port="$3"
  local cidr_or_group="$4"
  local type="${5:-cidr}"

  if [[ "$type" == "group" ]]; then
    aws ec2 authorize-security-group-ingress \
      --region "$AWS_REGION" \
      --group-id "$group_id" \
      --protocol "$protocol" \
      --port "$port" \
      --source-group "$cidr_or_group" \
      2>/dev/null || true
  else
    aws ec2 authorize-security-group-ingress \
      --region "$AWS_REGION" \
      --group-id "$group_id" \
      --protocol "$protocol" \
      --port "$port" \
      --cidr "$cidr_or_group" \
      2>/dev/null || true
  fi
}

ALB_SG_ID="$(get_or_create_sg "${ALB_SG_NAME:-alb-sg}" "ALB Security Group" "$VPC_ID")"
BASTION_SG_ID="$(get_or_create_sg "${BASTION_SG_NAME:-bastion-sg}" "Bastion Host Security Group" "$VPC_ID")"
APP_SG_ID="$(get_or_create_sg "${APP_SG_NAME:-app-sg}" "App Server Security Group" "$VPC_ID")"
DB_SG_ID="$(get_or_create_sg "${DB_SG_NAME:-db-sg}" "Database Security Group" "$VPC_ID")"
REDIS_SG_ID="$(get_or_create_sg "${REDIS_SG_NAME:-redis-sg}" "Redis Security Group" "$VPC_ID")"
JENKINS_SG_ID="$(get_or_create_sg "${JENKINS_SG_NAME:-jenkins-sg}" "Jenkins Master Security Group" "$VPC_ID")"
WORKER_SG_ID="$(get_or_create_sg "${WORKER_SG_NAME:-jenkins-worker-sg}" "Jenkins Worker Security Group" "$VPC_ID")"
MAVEN_SG_ID="$(get_or_create_sg "${MAVEN_SG_NAME:-maven-sg}" "Maven Security Group" "$VPC_ID")"
TRIVY_SG_ID="$(get_or_create_sg "${TRIVY_SG_NAME:-trivy-sg}" "Trivy Security Group" "$VPC_ID")"
SONAR_SG_ID="$(get_or_create_sg "${SONAR_SG_NAME:-sonarqube-sg}" "SonarQube Security Group" "$VPC_ID")"

echo "Configuring ingress rules for VPC ${VPC_ID}..."

ensure_rule "$ALB_SG_ID" tcp 80 0.0.0.0/0
ensure_rule "$ALB_SG_ID" tcp 443 0.0.0.0/0

ensure_rule "$BASTION_SG_ID" tcp 22 "$MY_CIDR"

ensure_rule "$APP_SG_ID" tcp 8080 "$ALB_SG_ID" group
ensure_rule "$APP_SG_ID" tcp 22 "$BASTION_SG_ID" group
ensure_rule "$APP_SG_ID" tcp 6379 "$REDIS_SG_ID" group

ensure_rule "$DB_SG_ID" tcp 3306 "$APP_SG_ID" group

ensure_rule "$REDIS_SG_ID" tcp 22 "$BASTION_SG_ID" group
ensure_rule "$REDIS_SG_ID" tcp 6379 "$APP_SG_ID" group

ensure_rule "$JENKINS_SG_ID" tcp 22 "$BASTION_SG_ID" group
ensure_rule "$JENKINS_SG_ID" tcp 8080 "$MY_CIDR"
ensure_rule "$JENKINS_SG_ID" tcp 50000 "$WORKER_SG_ID" group
ensure_rule "$JENKINS_SG_ID" tcp 9000 "$SONAR_SG_ID" group

ensure_rule "$WORKER_SG_ID" tcp 22 "$BASTION_SG_ID" group
ensure_rule "$WORKER_SG_ID" tcp 22 "$JENKINS_SG_ID" group
ensure_rule "$WORKER_SG_ID" tcp 50000 "$JENKINS_SG_ID" group

ensure_rule "$MAVEN_SG_ID" tcp 22 "$BASTION_SG_ID" group
ensure_rule "$MAVEN_SG_ID" tcp 22 "$JENKINS_SG_ID" group

ensure_rule "$TRIVY_SG_ID" tcp 22 "$BASTION_SG_ID" group
ensure_rule "$TRIVY_SG_ID" tcp 22 "$JENKINS_SG_ID" group

ensure_rule "$SONAR_SG_ID" tcp 22 "$BASTION_SG_ID" group
ensure_rule "$SONAR_SG_ID" tcp 9000 "$MY_CIDR"
ensure_rule "$SONAR_SG_ID" tcp 9000 "$JENKINS_SG_ID" group

echo "Security configuration completed."