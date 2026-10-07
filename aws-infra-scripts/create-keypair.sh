#!/usr/bin/env bash
set -euo pipefail

KEY_NAME="${KEY_NAME:-capstone-key}"
KEY_DIR="${KEY_DIR:-$HOME/.ssh}"
AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}"

mkdir -p "$KEY_DIR"

if ! aws ec2 describe-key-pairs --region "$AWS_REGION" --key-names "$KEY_NAME" >/dev/null 2>&1; then
  aws ec2 create-key-pair \
    --region "$AWS_REGION" \
    --key-name "$KEY_NAME" \
    --tag-specifications "ResourceType=key-pair,Tags=[{Key=Name,Value=${KEY_NAME}},{Key=${COMMON_TAG_KEY:-Project},Value=${COMMON_TAG_VALUE:-capstone-project}}]" \
    --query 'KeyMaterial' \
    --output text > "$KEY_DIR/${KEY_NAME}.pem"

  chmod 400 "$KEY_DIR/${KEY_NAME}.pem"
  echo "Created key pair: $KEY_NAME"
  echo "Private key saved at: $KEY_DIR/${KEY_NAME}.pem"
else
  echo "Key pair already exists: $KEY_NAME"
fi