#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Single shared build server to host both Maven and Trivy as Docker containers.
# This keeps the EC2 footprint minimal while still allowing Jenkins and SonarQube
# to reach the build and scan tools over the host network.
INSTANCE_NAME="${INSTANCE_NAME:-maven-trivy-server}"
SUBNET_NAME="${PUBLIC_SUBNET_NAME:-public-subnet-1}"
SECURITY_GROUP_NAME="${BUILD_SG_NAME:-maven-sg}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.medium}"
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

apt-get update
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

mkdir -p /opt/build-tools
cat > /opt/build-tools/docker-compose.yml <<'YAML'
version: "3.9"
services:
  maven:
    image: maven:3.9.9-eclipse-temurin-17
    container_name: maven-builder
    working_dir: /workspace
    volumes:
      - /opt/build-tools/workspace:/workspace
    stdin_open: true
    tty: true
    ports:
      - "18080:8080"
    command: ["bash", "-lc", "while true; do sleep 3600; done"]
    restart: unless-stopped

  trivy:
    image: aquasec/trivy:0.54.1
    container_name: trivy-scanner
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /opt/build-tools/workspace:/workspace
    stdin_open: true
    tty: true
    ports:
      - "18081:8080"
    command: ["sh", "-lc", "while true; do sleep 3600; done"]
    restart: unless-stopped
YAML

mkdir -p /opt/build-tools/workspace
/usr/bin/docker compose -f /opt/build-tools/docker-compose.yml up -d
/usr/bin/docker ps
EOF
)

INSTANCE_ID="$(create_instance "$INSTANCE_NAME" "$AMI_ID" "$SUBNET_ID" "$SG_ID" "$INSTANCE_TYPE" "$KEY_NAME" "" "$USER_DATA")"
wait_for_instance_running "$INSTANCE_ID"
print_instance_summary "$INSTANCE_ID" "$INSTANCE_NAME"
