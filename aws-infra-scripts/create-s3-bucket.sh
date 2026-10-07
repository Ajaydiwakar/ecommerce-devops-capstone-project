#!/usr/bin/env bash
set -euo pipefail

BUCKET_NAME="${BUCKET_NAME:-${S3_BUCKET_NAME:-ecommerce-product-images-426163621897}}"
AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}"

if aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "Using existing bucket: $BUCKET_NAME"
else
  if [[ "$AWS_REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" --no-cli-pager
  else
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" --create-bucket-configuration LocationConstraint="$AWS_REGION" --no-cli-pager
  fi
  echo "Created bucket: $BUCKET_NAME"
fi

aws s3api put-bucket-tagging \
  --bucket "$BUCKET_NAME" \
  --tagging "TagSet=[{Key=Name,Value=${BUCKET_NAME}},{Key=Purpose,Value=media-storage},{Key=${COMMON_TAG_KEY:-project},Value=${COMMON_TAG_VALUE:-capstone-project}}]" \
  --region "$AWS_REGION" \
  --no-cli-pager

aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
  --region "$AWS_REGION" \
  --no-cli-pager

echo "Bucket ready: $BUCKET_NAME"