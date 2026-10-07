#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

require_cmd aws

export AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$AWS_REGION}"
export COMMON_TAG_KEY="${COMMON_TAG_KEY:-project}"
export COMMON_TAG_VALUE="${COMMON_TAG_VALUE:-capstone-project}"
export KEY_NAME="${KEY_NAME:-capstone-key}"
export S3_BUCKET_NAME="${S3_BUCKET_NAME:-${BUCKET_NAME:-ecommerce-product-images-426163621897}}"
export BUCKET_NAME="${S3_BUCKET_NAME}"
export APP_BUCKET_NAME="${S3_BUCKET_NAME}"

run_step() {
  local step_name="$1"
  shift
  echo
  echo "============================================================"
  echo "== $step_name"
  echo "============================================================"
  "$@"
}

echo "Provisioning Capstone project infrastructure..."
echo "Region: ${AWS_REGION}"
echo "Key Pair: ${KEY_NAME}"
echo "Project Tag: ${COMMON_TAG_KEY}=${COMMON_TAG_VALUE}"
echo "S3 Bucket: ${S3_BUCKET_NAME}"

aws sts get-caller-identity --output table >/dev/null

run_step "Create EC2 Key Pair" bash "$SCRIPT_DIR/aws-infra-scripts/create-keypair.sh"
run_step "Configure AWS security groups" bash "$SCRIPT_DIR/aws-infra-scripts/configure-security.sh"
run_step "Ensure S3 bucket exists and is mapped" bash "$SCRIPT_DIR/aws-infra-scripts/create-s3-bucket.sh"

run_step "Create bastion IAM role + instance profile" bash "$SCRIPT_DIR/aws-roles/create-bastion-role.sh"
run_step "Create app IAM role + instance profile" bash "$SCRIPT_DIR/aws-roles/create-app-instance-role.sh"
run_step "Create shared EC2 IAM profile" bash "$SCRIPT_DIR/aws-roles/create-ec2-iam-profile.sh"

# Keep the deployment within the EC2 vCPU quota by consolidating Maven and Trivy
# onto a single build host and using an autoscaled app tier behind an ALB.
run_step "Launch bastion host" bash "$SCRIPT_DIR/aws-infra-scripts/create-bastion.sh"
run_step "Create Jenkins master instance" bash "$SCRIPT_DIR/aws-infra-scripts/create-jenkins-master.sh"
run_step "Create Jenkins worker instance" bash "$SCRIPT_DIR/aws-infra-scripts/create-jenkins-worker.sh"
run_step "Create SonarQube server" bash "$SCRIPT_DIR/aws-infra-scripts/create-sonarqube-server.sh"
run_step "Create Redis Docker container on EC2" bash "$SCRIPT_DIR/aws-infra-scripts/create-redis-server.sh"
run_step "Create app server ASG with launch template" bash "$SCRIPT_DIR/aws-infra-scripts/create-app-asg.sh"
run_step "Create ALB for end-user to app server routing" bash "$SCRIPT_DIR/aws-infra-scripts/create-alb.sh"
run_step "Launch shared Maven + Trivy build server" bash "$SCRIPT_DIR/aws-infra-scripts/create-build-server.sh"
run_step "Create RDS database" bash "$SCRIPT_DIR/aws-infra-scripts/create-rds.sh"

echo
echo "All AWS infrastructure and IAM roles have been provisioned successfully."
echo "Project tag used: ${COMMON_TAG_KEY}=${COMMON_TAG_VALUE}"
echo "Bucket mapped: ${S3_BUCKET_NAME}"
