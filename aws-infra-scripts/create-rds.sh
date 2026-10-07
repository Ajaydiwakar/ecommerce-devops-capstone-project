#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

DB_IDENTIFIER="${DB_IDENTIFIER:-capstone-ecommerce-db}"
DB_NAME="${DB_NAME:-capstone-ecommerce}"
DB_USERNAME="${DB_USERNAME:-admin}"
DB_PASSWORD="${DB_PASSWORD:-StrongPass123!}"
DB_INSTANCE_CLASS="${DB_INSTANCE_CLASS:-db.t3.micro}"
DB_STORAGE="${DB_STORAGE:-20}"
DB_ENGINE="${DB_ENGINE:-mysql}"
# Use an engine version that AWS RDS actually offers for db.t3.micro in this account/region.
DB_ENGINE_VERSION="${DB_ENGINE_VERSION:-8.0.46}"
DB_SUBNET_GROUP_NAME="${DB_SUBNET_GROUP_NAME:-capstone-db-subnet-group}"
DB_SECURITY_GROUP_NAME="${DB_SECURITY_GROUP_NAME:-db-sg}"

VPC_ID="$(get_vpc_id)"
DB_SG_ID="$(get_security_group_id "$DB_SECURITY_GROUP_NAME" "$VPC_ID")"

# RDS must be placed only in the private subnet set for this VPC.
# Using all subnets can leave stale or mixed-VPC subnet groups and trigger capacity faults.
SUBNET_IDS="$(aws ec2 describe-subnets --region "$AWS_REGION" \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=map-public-ip-on-launch,Values=false" \
  --query 'Subnets[*].SubnetId' --output text | tr '\n' ' ' | xargs)"

if [[ -z "$SUBNET_IDS" ]]; then
  SUBNET_IDS="$(aws ec2 describe-subnets --region "$AWS_REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'Subnets[*].SubnetId' --output text | tr '\n' ' ' | xargs)"
fi

ensure_db_subnet_group() {
  local subnet_group_exists
  local existing_vpc_id

  subnet_group_exists="$(aws rds describe-db-subnet-groups \
    --region "$AWS_REGION" \
    --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" \
    --query 'DBSubnetGroups[0].DBSubnetGroupName' \
    --output text 2>/dev/null || true)"

  existing_vpc_id="$(aws rds describe-db-subnet-groups \
    --region "$AWS_REGION" \
    --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" \
    --query 'DBSubnetGroups[0].VpcId' \
    --output text 2>/dev/null || true)"

  if [[ -n "$subnet_group_exists" && "$subnet_group_exists" != "None" ]]; then
    if [[ -n "$existing_vpc_id" && "$existing_vpc_id" != "$VPC_ID" ]]; then
      echo "Deleting stale RDS subnet group '${DB_SUBNET_GROUP_NAME}' in VPC '${existing_vpc_id}'..."
      aws rds delete-db-subnet-group \
        --region "$AWS_REGION" \
        --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" \
        >/dev/null 2>&1 || true
      subnet_group_exists=""
    fi
  fi

  if [[ -z "$subnet_group_exists" || "$subnet_group_exists" == "None" ]]; then
    echo "Creating RDS Subnet Group '${DB_SUBNET_GROUP_NAME}' in VPC '${VPC_ID}'..."
    aws rds create-db-subnet-group \
      --region "$AWS_REGION" \
      --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" \
      --db-subnet-group-description "Private subnet group for capstone database" \
      --subnet-ids $SUBNET_IDS \
      --tags Key=Name,Value="$DB_SUBNET_GROUP_NAME" Key=${COMMON_TAG_KEY:-Project},Value="${COMMON_TAG_VALUE:-capstone-project}"
  fi
}

ensure_db_subnet_group

if ! aws rds describe-db-instances --region "$AWS_REGION" --db-instance-identifier "$DB_IDENTIFIER" >/dev/null 2>&1; then
  echo "Creating RDS MySQL Instance '${DB_IDENTIFIER}'..."
  aws rds create-db-instance \
    --region "$AWS_REGION" \
    --db-instance-identifier "$DB_IDENTIFIER" \
    --db-instance-class "$DB_INSTANCE_CLASS" \
    --engine "$DB_ENGINE" \
    --engine-version "$DB_ENGINE_VERSION" \
    --allocated-storage "$DB_STORAGE" \
    --db-name "$DB_NAME" \
    --master-username "$DB_USERNAME" \
    --master-user-password "$DB_PASSWORD" \
    --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" \
    --vpc-security-group-ids "$DB_SG_ID" \
    --backup-retention-period 7 \
    --no-storage-encrypted \
    --no-publicly-accessible \
    --no-multi-az \
    --no-deletion-protection \
    --tags Key=Name,Value="$DB_IDENTIFIER" Key=${COMMON_TAG_KEY:-project},Value="${COMMON_TAG_VALUE:-capstone-project}"

  echo "Waiting for RDS instance to become available..."
  aws rds wait db-instance-available --region "$AWS_REGION" --db-instance-identifier "$DB_IDENTIFIER"
else
  echo "RDS instance '${DB_IDENTIFIER}' already exists. Skipping creation."
fi

DB_HOST="$(aws rds describe-db-instances --region "$AWS_REGION" --db-instance-identifier "$DB_IDENTIFIER" --query 'DBInstances[0].Endpoint.Address' --output text)"

echo "RDS Endpoint: ${DB_HOST}"
echo "DB Name: ${DB_NAME}"
echo "DB User: ${DB_USERNAME}"