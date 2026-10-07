#!/usr/bin/env bash
set -euo pipefail

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

require_cmd aws

COMMON_TAG_KEY="${COMMON_TAG_KEY:-project}"
COMMON_TAG_VALUE="${COMMON_TAG_VALUE:-capstone-project}"

AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}"
export AWS_REGION
export COMMON_TAG_KEY COMMON_TAG_VALUE

aws_account_id() {
  aws sts get-caller-identity --query Account --output text --region "$AWS_REGION"
}

get_vpc_id() {
  local vpc_name="${1:-${VPC_NAME:-capstone-vpc}}"
  local vpc_id

  # 1. Look for VPC matching Name tag
  vpc_id="$(aws ec2 describe-vpcs --region "$AWS_REGION" --filters "Name=tag:Name,Values=${vpc_name}" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)"

  # 2. Fallback to first non-default VPC
  if [ -z "$vpc_id" ] || [ "$vpc_id" = "None" ]; then
    vpc_id="$(aws ec2 describe-vpcs --region "$AWS_REGION" --filters "Name=is-default,Values=false" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)"
  fi

  # 3. Fallback to default VPC
  if [ -z "$vpc_id" ] || [ "$vpc_id" = "None" ]; then
    vpc_id="$(aws ec2 describe-vpcs --region "$AWS_REGION" --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)"
  fi

  if [ -z "$vpc_id" ] || [ "$vpc_id" = "None" ]; then
    echo "ERROR: No valid VPC found in region ${AWS_REGION}." >&2
    exit 1
  fi
  echo "$vpc_id"
}

get_subnet_id() {
  local subnet_name="${1:-${SUBNET_NAME:-public-subnet-1}}"
  local vpc_id="${2:-$(get_vpc_id)}"
  local subnet_id

  # Search by exact Tag Name
  subnet_id="$(aws ec2 describe-subnets --region "$AWS_REGION" --filters "Name=vpc-id,Values=${vpc_id}" "Name=tag:Name,Values=${subnet_name}" --query 'Subnets[0].SubnetId' --output text 2>/dev/null || true)"

  # Fallback: Wildcard match on Tag Name
  if [ -z "$subnet_id" ] || [ "$subnet_id" = "None" ]; then
    subnet_id="$(aws ec2 describe-subnets --region "$AWS_REGION" --filters "Name=vpc-id,Values=${vpc_id}" "Name=tag:Name,Values=*${subnet_name}*" --query 'Subnets[0].SubnetId' --output text 2>/dev/null || true)"
  fi

  # Fallback based on Public / Private characteristics
  if [ -z "$subnet_id" ] || [ "$subnet_id" = "None" ]; then
    case "$subnet_name" in
      *public*)
        subnet_id="$(aws ec2 describe-subnets --region "$AWS_REGION" --filters "Name=vpc-id,Values=${vpc_id}" "Name=map-public-ip-on-launch,Values=true" --query 'Subnets[0].SubnetId' --output text 2>/dev/null || true)"
        ;;
      *)
        subnet_id="$(aws ec2 describe-subnets --region "$AWS_REGION" --filters "Name=vpc-id,Values=${vpc_id}" "Name=map-public-ip-on-launch,Values=false" --query 'Subnets[0].SubnetId' --output text 2>/dev/null || true)"
        ;;
    esac
  fi

  # Absolute Fallback: Any available subnet in VPC
  if [ -z "$subnet_id" ] || [ "$subnet_id" = "None" ]; then
    subnet_id="$(aws ec2 describe-subnets --region "$AWS_REGION" --filters "Name=vpc-id,Values=${vpc_id}" --query 'Subnets[0].SubnetId' --output text 2>/dev/null || true)"
  fi

  if [ -z "$subnet_id" ] || [ "$subnet_id" = "None" ]; then
    echo "ERROR: No subnet found in VPC ${vpc_id}." >&2
    exit 1
  fi
  echo "$subnet_id"
}

ensure_public_subnet_layout() {
  local vpc_id="${1:-$(get_vpc_id)}"
  local igw_id
  local public_rt_id

  igw_id="$(aws ec2 describe-internet-gateways --region "$AWS_REGION" --filters "Name=attachment.vpc-id,Values=${vpc_id}" --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null || true)"

  if [ -z "$igw_id" ] || [ "$igw_id" = "None" ]; then
    igw_id="$(aws ec2 create-internet-gateway --region "$AWS_REGION" --query 'InternetGateway.InternetGatewayId' --output text)"
    aws ec2 attach-internet-gateway --region "$AWS_REGION" --vpc-id "$vpc_id" --internet-gateway-id "$igw_id" >/dev/null
  fi

  public_rt_id="$(aws ec2 describe-route-tables --region "$AWS_REGION" --filters "Name=vpc-id,Values=${vpc_id}" --query 'RouteTables[?length(Routes[?GatewayId!=`local` && starts_with(GatewayId, `igw-`)]) > `0`].RouteTableId | [0]' --output text 2>/dev/null || true)"

  if [ -z "$public_rt_id" ] || [ "$public_rt_id" = "None" ]; then
    public_rt_id="$(aws ec2 create-route-table --region "$AWS_REGION" --vpc-id "$vpc_id" --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${vpc_id}-public-route-table},{Key=${COMMON_TAG_KEY},Value=${COMMON_TAG_VALUE}}]" --query 'RouteTable.RouteTableId' --output text)"
    aws ec2 create-route --region "$AWS_REGION" --route-table-id "$public_rt_id" --destination-cidr-block 0.0.0.0/0 --gateway-id "$igw_id" >/dev/null
  fi

  for subnet_id in $(aws ec2 describe-subnets --region "$AWS_REGION" --filters "Name=vpc-id,Values=${vpc_id}" "Name=tag:Name,Values=*public*" --query 'Subnets[].SubnetId' --output text 2>/dev/null); do
    aws ec2 modify-subnet-attribute --region "$AWS_REGION" --subnet-id "$subnet_id" --map-public-ip-on-launch >/dev/null 2>&1 || true
    aws ec2 associate-route-table --region "$AWS_REGION" --subnet-id "$subnet_id" --route-table-id "$public_rt_id" >/dev/null 2>&1 || true
  done

  echo "$public_rt_id"
}

get_public_subnet_id() {
  local subnet_name="${1:-${PUBLIC_SUBNET_NAME:-public-subnet-1}}"
  local vpc_id="${2:-$(get_vpc_id)}"
  local subnet_id

  ensure_public_subnet_layout "$vpc_id" >/dev/null

  subnet_id="$(aws ec2 describe-subnets --region "$AWS_REGION" --filters "Name=vpc-id,Values=${vpc_id}" "Name=tag:Name,Values=${subnet_name}" "Name=map-public-ip-on-launch,Values=true" --query 'Subnets[0].SubnetId' --output text 2>/dev/null || true)"

  if [ -z "$subnet_id" ] || [ "$subnet_id" = "None" ]; then
    subnet_id="$(aws ec2 describe-subnets --region "$AWS_REGION" --filters "Name=vpc-id,Values=${vpc_id}" "Name=tag:Name,Values=*${subnet_name}*" "Name=map-public-ip-on-launch,Values=true" --query 'Subnets[0].SubnetId' --output text 2>/dev/null || true)"
  fi

  if [ -z "$subnet_id" ] || [ "$subnet_id" = "None" ]; then
    subnet_id="$(aws ec2 describe-subnets --region "$AWS_REGION" --filters "Name=vpc-id,Values=${vpc_id}" "Name=map-public-ip-on-launch,Values=true" --query 'Subnets[0].SubnetId' --output text 2>/dev/null || true)"
  fi

  if [ -z "$subnet_id" ] || [ "$subnet_id" = "None" ]; then
    echo "ERROR: No public subnet found in VPC ${vpc_id}. The bastion must run in a public subnet with internet access." >&2
    exit 1
  fi

  echo "$subnet_id"
}

get_security_group_id() {
  local sg_name="${1:-${SECURITY_GROUP_NAME:-default}}"
  local vpc_id="${2:-$(get_vpc_id)}"
  local sg_id

  sg_id="$(aws ec2 describe-security-groups --region "$AWS_REGION" --filters "Name=vpc-id,Values=${vpc_id}" "Name=group-name,Values=${sg_name}" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)"

  if [ -z "$sg_id" ] || [ "$sg_id" = "None" ]; then
    sg_id="$(aws ec2 describe-security-groups --region "$AWS_REGION" --filters "Name=vpc-id,Values=${vpc_id}" "Name=group-name,Values=default" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)"
  fi
  echo "$sg_id"
}

get_ami_id() {
  local owner="${1:-amazon}"
  local name_pattern="${2:-al2023-ami-*-x86_64}"
  aws ec2 describe-images \
    --region "$AWS_REGION" \
    --owners "$owner" \
    --filters "Name=name,Values=${name_pattern}" "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text
}

get_ubuntu_ami_id() {
  aws ssm get-parameter \
    --region "$AWS_REGION" \
    --name "/aws/service/canonical/ubuntu/server/jammy/stable/current/amd64/hvm/ebs-gp2/ami-id" \
    --query 'Parameter.Value' \
    --output text
}

find_instance_by_name() {
  local instance_name="${1}"

  aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --filters "Name=tag:Name,Values=${instance_name}" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[0].InstanceId' \
    --output text 2>/dev/null | awk 'NF { print; exit }' || true
}

create_instance() {
  local instance_name="${1}"
  local ami_id="${2}"
  local subnet_id="${3}"
  local sg_id="${4}"
  local instance_type="${5:-t3.micro}"
  local key_name="${6:-${KEY_NAME:-capstone-key}}"
  local instance_profile="${7:-}"
  local user_data="${8:-}"

  if [ -z "$subnet_id" ] || [ -z "$sg_id" ] || [ "$subnet_id" = "None" ] || [ "$sg_id" = "None" ]; then
    echo "ERROR: Valid Subnet ID and Security Group ID are required for instance '${instance_name}'." >&2
    exit 1
  fi

  local run_args=(
    ec2 run-instances
    --region "$AWS_REGION"
    --image-id "$ami_id"
    --count 1
    --instance-type "$instance_type"
    --key-name "$key_name"
    --subnet-id "$subnet_id"
    --security-group-ids "$sg_id"
    --associate-public-ip-address
  )

  if [ -n "$instance_profile" ]; then
    run_args+=(--iam-instance-profile "Name=${instance_profile}")
  fi

  if [ -n "$user_data" ]; then
    run_args+=(--user-data "$user_data")
  fi

  aws "${run_args[@]}" \
    --tag-specifications \
      "ResourceType=instance,Tags=[{Key=Name,Value=${instance_name}},{Key=${COMMON_TAG_KEY},Value=${COMMON_TAG_VALUE}}]" \
      "ResourceType=volume,Tags=[{Key=Name,Value=${instance_name}-volume},{Key=${COMMON_TAG_KEY},Value=${COMMON_TAG_VALUE}}]" \
    --query 'Instances[0].InstanceId' \
    --output text
}

wait_for_instance_running() {
  local instance_id="${1}"
  aws ec2 wait instance-running --region "$AWS_REGION" --instance-ids "$instance_id"
}

ensure_instance_has_public_ip() {
  local instance_id="${1}"
  local instance_name="${2:-${instance_id}}"
  local public_ip

  public_ip="$(aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --instance-ids "$instance_id" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text 2>/dev/null || true)"

  if [ -n "$public_ip" ] && [ "$public_ip" != "None" ] && [ "$public_ip" != "null" ]; then
    echo "Instance '${instance_name}' already has a public IP: ${public_ip}"
    return 0
  fi

  local allocation_id
  allocation_id="$(aws ec2 allocate-address --region "$AWS_REGION" --domain vpc --query 'AllocationId' --output text)"
  aws ec2 associate-address \
    --region "$AWS_REGION" \
    --instance-id "$instance_id" \
    --allocation-id "$allocation_id" >/dev/null

  public_ip="$(aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --instance-ids "$instance_id" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)"

  echo "Associated public IP ${public_ip} with instance '${instance_name}' (${instance_id})"
}

print_instance_summary() {
  local instance_id="${1}"
  local instance_name="${2}"
  aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --instance-ids "$instance_id" \
    --query 'Reservations[0].Instances[0].[InstanceId,InstanceType,PrivateIpAddress,PublicIpAddress,State.Name]' \
    --output table
  echo "Successfully launched instance: ${instance_name} (${instance_id})"
}
