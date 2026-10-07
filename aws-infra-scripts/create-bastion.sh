#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

INSTANCE_NAME="${INSTANCE_NAME:-bastion-host}"
SUBNET_NAME="${PUBLIC_SUBNET_NAME:-public-subnet-1}"
SECURITY_GROUP_NAME="${BASTION_SG_NAME:-bastion-sg}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.micro}"
KEY_NAME="${KEY_NAME:-capstone-key}"
PROFILE_NAME="bastion-admin-role-profile"

VPC_ID="$(get_vpc_id)"
ensure_public_subnet_layout "$VPC_ID" >/dev/null
SUBNET_ID="$(get_public_subnet_id "$SUBNET_NAME" "$VPC_ID")"
SG_ID="$(get_security_group_id "$SECURITY_GROUP_NAME" "$VPC_ID")"
AMI_ID="$(get_ubuntu_ami_id)"

EXISTING_INSTANCE_ID="$(find_instance_by_name "$INSTANCE_NAME")"
if [ -n "$EXISTING_INSTANCE_ID" ] && [ "$EXISTING_INSTANCE_ID" != "None" ]; then
  PUBLIC_IP="$(aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$EXISTING_INSTANCE_ID" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null || true)"

  if [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "None" ] && [ "$PUBLIC_IP" != "null" ]; then
    echo "Instance '${INSTANCE_NAME}' already exists (${EXISTING_INSTANCE_ID}) and already has a public IP. Skipping creation."
    wait_for_instance_running "$EXISTING_INSTANCE_ID"
    aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$EXISTING_INSTANCE_ID" --query 'Reservations[0].Instances[0].[InstanceId,InstanceType,PrivateIpAddress,PublicIpAddress,State.Name]' --output table
    exit 0
  fi

  echo "Instance '${INSTANCE_NAME}' exists but does not have a public IP. Recreating it in a public subnet."
  aws ec2 terminate-instances --region "$AWS_REGION" --instance-ids "$EXISTING_INSTANCE_ID" >/dev/null
  aws ec2 wait instance-terminated --region "$AWS_REGION" --instance-ids "$EXISTING_INSTANCE_ID"
fi

INSTANCE_ID="$(create_instance "$INSTANCE_NAME" "$AMI_ID" "$SUBNET_ID" "$SG_ID" "$INSTANCE_TYPE" "$KEY_NAME" "$PROFILE_NAME")"
wait_for_instance_running "$INSTANCE_ID"
ensure_instance_has_public_ip "$INSTANCE_ID" "$INSTANCE_NAME"
print_instance_summary "$INSTANCE_ID" "$INSTANCE_NAME"