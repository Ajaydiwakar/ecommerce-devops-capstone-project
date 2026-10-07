#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

INSTANCE_NAME="${INSTANCE_NAME:-redis-server}"
SUBNET_NAME="${PRIVATE_SUBNET_NAME:-private-subnet-1}"
SECURITY_GROUP_NAME="${REDIS_SG_NAME:-redis-sg}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.micro}"
KEY_NAME="${KEY_NAME:-capstone-key}"

VPC_ID="$(get_vpc_id)"
SUBNET_ID="$(get_subnet_id "$SUBNET_NAME" "$VPC_ID")"
SG_ID="$(get_security_group_id "$SECURITY_GROUP_NAME" "$VPC_ID")"
AMI_ID="$(get_ubuntu_ami_id)"

EXISTING_INSTANCE_ID="$(find_instance_by_name "$INSTANCE_NAME")"
if [ -n "$EXISTING_INSTANCE_ID" ] && [ "$EXISTING_INSTANCE_ID" != "None" ]; then
  echo "Instance '${INSTANCE_NAME}' already exists (${EXISTING_INSTANCE_ID}). Skipping creation."
  aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$EXISTING_INSTANCE_ID" --query 'Reservations[0].Instances[0].[InstanceId,InstanceType,PrivateIpAddress,PublicIpAddress,State.Name]' --output table
  exit 0
fi

USER_DATA=$(cat <<'EOF'
#!/bin/bash
set -eux
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

mkdir -p /opt/redis-data

docker run -d \
  --name ecommerce-redis \
  --restart unless-stopped \
  -p 6379:6379 \
  -v /opt/redis-data:/data \
  redis:7-alpine \
  redis-server --appendonly yes --save 60 1 --protected-mode no

docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
EOF
)

INSTANCE_ID="$(create_instance "$INSTANCE_NAME" "$AMI_ID" "$SUBNET_ID" "$SG_ID" "$INSTANCE_TYPE" "$KEY_NAME" "" "$USER_DATA")"
wait_for_instance_running "$INSTANCE_ID"
print_instance_summary "$INSTANCE_ID" "$INSTANCE_NAME"
