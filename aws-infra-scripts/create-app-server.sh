#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

INSTANCE_NAME="${INSTANCE_NAME:-app-server-1}"
SUBNET_NAME="${PRIVATE_SUBNET_NAME:-private-subnet-1}"
SECURITY_GROUP_NAME="${APP_SG_NAME:-app-sg}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.small}"
KEY_NAME="${KEY_NAME:-capstone-key}"
PROFILE_NAME="app-instance-role-profile"

VPC_ID="$(get_vpc_id)"
SUBNET_ID="$(get_subnet_id "$SUBNET_NAME" "$VPC_ID")"
SG_ID="$(get_security_group_id "$SECURITY_GROUP_NAME" "$VPC_ID")"
AMI_ID="$(get_ami_id "amazon" "al2023-ami-*-x86_64")"

INSTANCE_ID="$(create_instance "$INSTANCE_NAME" "$AMI_ID" "$SUBNET_ID" "$SG_ID" "$INSTANCE_TYPE" "$KEY_NAME" "$PROFILE_NAME")"
wait_for_instance_running "$INSTANCE_ID"
print_instance_summary "$INSTANCE_ID" "$INSTANCE_NAME"