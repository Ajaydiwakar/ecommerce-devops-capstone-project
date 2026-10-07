#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

APP_NAME="${APP_NAME:-capstone-app}"
ASG_NAME="${ASG_NAME:-capstone-app-asg}"
LT_NAME="${LT_NAME:-capstone-app-lt}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.small}"
KEY_NAME="${KEY_NAME:-capstone-key}"
MIN_SIZE="${MIN_SIZE:-1}"
MAX_SIZE="${MAX_SIZE:-4}"
DESIRED_CAPACITY="${DESIRED_CAPACITY:-2}"
APP_SG_NAME="${APP_SG_NAME:-app-sg}"
APP_JAR_S3_URI="${APP_JAR_S3_URI:-s3://${S3_BUCKET_NAME:-ecommerce-product-images-426163621897}/releases/ecommerce-app.jar}"

VPC_ID="$(get_vpc_id)"
APP_SG_ID="$(get_security_group_id "$APP_SG_NAME" "$VPC_ID")"

# Use private subnets for the application layer behind the ALB.
SUBNET_IDS="$(aws ec2 describe-subnets --region "$AWS_REGION" \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=map-public-ip-on-launch,Values=false" \
  --query 'Subnets[*].SubnetId' --output text | tr '\n' ' ' | xargs)"

if [[ -z "$SUBNET_IDS" ]]; then
  SUBNET_IDS="$(aws ec2 describe-subnets --region "$AWS_REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'Subnets[*].SubnetId' --output text | tr '\n' ' ' | xargs)"
fi

SUBNET_IDS_COMMA="$(echo "$SUBNET_IDS" | tr ' ' ',')"

if aws ec2 describe-launch-templates --launch-template-names "$LT_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "Deleting existing launch template '${LT_NAME}'..."
  aws ec2 delete-launch-template --region "$AWS_REGION" --launch-template-name "$LT_NAME" >/dev/null 2>&1 || true
fi

REDIS_HOST_VALUE_FOR_TEMPLATE="${REDIS_HOST_VALUE_FOR_TEMPLATE:-$(aws ec2 describe-instances --region "${AWS_REGION:-us-east-1}" \
  --filters "Name=tag:Name,Values=redis-server" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[0].PrivateIpAddress' --output text 2>/dev/null || echo redis)}"

cat > /tmp/capstone-app-user-data.sh <<EOF
#!/bin/bash
set -eux

# Install Java runtime for the Spring Boot app.
yum update -y
amazon-linux-extras enable java-openjdk17
yum install -y java-17-amazon-corretto jq aws-cli

mkdir -p /opt/ecommerce-app
mkdir -p /var/log/ecommerce

REDIS_HOST_VALUE="$(aws ec2 describe-instances --region ${AWS_REGION:-us-east-1} \
  --filters "Name=tag:Name,Values=redis-server" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[0].PrivateIpAddress' --output text 2>/dev/null || echo redis)"

cat > /etc/ecommerce-app.env <<ENV
DB_HOST=${DB_HOST:-mysql}
DB_PORT=${DB_PORT:-3306}
DB_NAME=${DB_NAME:-ecommerce}
DB_USERNAME=${DB_USERNAME:-admin}
DB_PASSWORD=${DB_PASSWORD:-password}
REDIS_HOST=${REDIS_HOST:-${REDIS_HOST_VALUE_FOR_TEMPLATE}}
REDIS_PORT=${REDIS_PORT:-6379}
AWS_REGION=${AWS_REGION:-us-east-1}
S3_BUCKET=${S3_BUCKET:-${S3_BUCKET_NAME:-ecommerce-product-images-426163621897}}
ENV

# Download the built Spring Boot jar from S3 if present.
if aws s3 cp "${APP_JAR_S3_URI}" /opt/ecommerce-app/ecommerce-app.jar; then
  echo "App artifact downloaded from ${APP_JAR_S3_URI}"
else
  echo "No app artifact found at ${APP_JAR_S3_URI}; creating a placeholder app service so the instance boots cleanly."
  cat > /opt/ecommerce-app/ecommerce-app.jar <<'PLACEHOLDER'
placeholder
PLACEHOLDER
fi

cat > /etc/systemd/system/ecommerce-app.service <<'SERVICE'
[Unit]
Description=Ecommerce Spring Boot Application
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/ecommerce-app
EnvironmentFile=/etc/ecommerce-app.env
ExecStart=/usr/bin/java -jar /opt/ecommerce-app/ecommerce-app.jar --server.port=8080
Restart=always
RestartSec=10
User=root
Group=root

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable ecommerce-app.service
systemctl start ecommerce-app.service
EOF

USER_DATA_B64="$(base64 -i /tmp/capstone-app-user-data.sh | tr -d '\n')"

cat > /tmp/capstone-app-launch-template.json <<JSON
{
  "LaunchTemplateName": "${LT_NAME}",
  "VersionDescription": "Initial app server launch template",
  "LaunchTemplateData": {
    "ImageId": "$(get_ami_id "amazon" "al2023-ami-*-x86_64")",
    "InstanceType": "${INSTANCE_TYPE}",
    "KeyName": "${KEY_NAME}",
    "UserData": "${USER_DATA_B64}",
    "NetworkInterfaces": [
      {
        "DeviceIndex": 0,
        "AssociatePublicIpAddress": false,
        "DeleteOnTermination": true,
        "Groups": ["${APP_SG_ID}"]
      }
    ],
    "TagSpecifications": [
      {
        "ResourceType": "instance",
        "Tags": [
          {"Key": "Name", "Value": "${APP_NAME}"},
          {"Key": "project", "Value": "${COMMON_TAG_VALUE:-capstone-project}"}
        ]
      },
      {
        "ResourceType": "volume",
        "Tags": [
          {"Key": "Name", "Value": "${APP_NAME}-volume"},
          {"Key": "project", "Value": "${COMMON_TAG_VALUE:-capstone-project}"}
        ]
      }
    ]
  }
}
JSON

aws ec2 create-launch-template --region "$AWS_REGION" --cli-input-json file:///tmp/capstone-app-launch-template.json >/dev/null

ASG_EXISTS="$(aws autoscaling describe-auto-scaling-groups --region "$AWS_REGION" \
  --query "AutoScalingGroups[?AutoScalingGroupName=='${ASG_NAME}'].AutoScalingGroupName | [0]" \
  --output text 2>/dev/null || true)"

if [[ -n "$ASG_EXISTS" && "$ASG_EXISTS" != "None" ]]; then
  echo "Updating existing auto scaling group '${ASG_NAME}'..."
  aws autoscaling update-auto-scaling-group \
    --region "$AWS_REGION" \
    --auto-scaling-group-name "$ASG_NAME" \
    --launch-template "LaunchTemplateName=${LT_NAME},Version=\$Latest" \
    --min-size "$MIN_SIZE" \
    --max-size "$MAX_SIZE" \
    --desired-capacity "$DESIRED_CAPACITY" \
    --vpc-zone-identifier "$SUBNET_IDS_COMMA"
else
  echo "Creating auto scaling group '${ASG_NAME}'..."
  aws autoscaling create-auto-scaling-group \
    --region "$AWS_REGION" \
    --auto-scaling-group-name "$ASG_NAME" \
    --launch-template "LaunchTemplateName=${LT_NAME},Version=\$Latest" \
    --min-size "$MIN_SIZE" \
    --max-size "$MAX_SIZE" \
    --desired-capacity "$DESIRED_CAPACITY" \
    --vpc-zone-identifier "$SUBNET_IDS_COMMA" \
    --health-check-type EC2 \
    --health-check-grace-period 300 \
    --tags \
      "ResourceId=${ASG_NAME},ResourceType=auto-scaling-group,Key=Name,Value=${APP_NAME},PropagateAtLaunch=true" \
      "ResourceId=${ASG_NAME},ResourceType=auto-scaling-group,Key=project,Value=${COMMON_TAG_VALUE:-capstone-project},PropagateAtLaunch=true"
fi

echo "ASG '${ASG_NAME}' created with custom launch template and tagging."
