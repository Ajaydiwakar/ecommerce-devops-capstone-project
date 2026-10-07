#!/usr/bin/env bash
set -euo pipefail

ROLE_NAME="${ROLE_NAME:-app-instance-role}"
POLICY_NAME="${POLICY_NAME:-app-instance-s3-read-policy}"
BUCKET_NAME="${BUCKET_NAME:-${APP_BUCKET_NAME:-${S3_BUCKET_NAME:-ecommerce-product-images-426163621897}}}"
INSTANCE_PROFILE_NAME="${ROLE_NAME}-profile"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

cat > /tmp/app-role-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Service": "ec2.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

if ! aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document file:///tmp/app-role-trust-policy.json \
    --tags Key=Name,Value="$ROLE_NAME" Key=${COMMON_TAG_KEY:-Project},Value="${COMMON_TAG_VALUE:-capstone-project}" \
    --query 'Role.Arn' \
    --output text
fi

cat > /tmp/app-s3-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadMediaFromBucket",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ]
    }
  ]
}
EOF

POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"
if ! aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document file:///tmp/app-s3-policy.json \
    --tags Key=Name,Value="$POLICY_NAME" Key=${COMMON_TAG_KEY:-Project},Value="${COMMON_TAG_VALUE:-capstone-project}" \
    --query 'Policy.Arn' \
    --output text
fi

aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN"

if ! aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" >/dev/null 2>&1; then
  aws iam create-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" --tags Key=Name,Value="$INSTANCE_PROFILE_NAME" Key=${COMMON_TAG_KEY:-Project},Value="${COMMON_TAG_VALUE:-capstone-project}" >/dev/null
fi

aws iam add-role-to-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" --role-name "$ROLE_NAME" >/dev/null 2>&1 || true

echo "App Instance IAM Role & Profile Ready: $INSTANCE_PROFILE_NAME"