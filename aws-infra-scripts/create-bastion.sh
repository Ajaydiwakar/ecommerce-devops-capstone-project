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
SUBNET_ID="$(get_subnet_id "$SUBNET_NAME" "$VPC_ID")"
SG_ID="$(get_security_group_id "$SECURITY_GROUP_NAME" "$VPC_ID")"
AMI_ID="$(get_ubuntu_ami_id)"

EXISTING_INSTANCE_ID="$(find_instance_by_name "$INSTANCE_NAME")"
if [ -n "$EXISTING_INSTANCE_ID" ] && [ "$EXISTING_INSTANCE_ID" != "None" ]; then
  echo "Instance '${INSTANCE_NAME}' already exists (${EXISTING_INSTANCE_ID}). Skipping creation."
  aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$EXISTING_INSTANCE_ID" --query 'Reservations[0].Instances[0].[InstanceId,InstanceType,PrivateIpAddress,PublicIpAddress,State.Name]' --output table
  exit 0
fi

INSTANCE_ID="$(create_instance "$INSTANCE_NAME" "$AMI_ID" "$SUBNET_ID" "$SG_ID" "$INSTANCE_TYPE" "$KEY_NAME" "$PROFILE_NAME")"
wait_for_instance_running "$INSTANCE_ID"
print_instance_summary "$INSTANCE_ID" "$INSTANCE_NAME"