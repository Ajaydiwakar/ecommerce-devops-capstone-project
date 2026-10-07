#!/usr/bin/env bash
set -euo pipefail

ROLE_NAME="${ROLE_NAME:-app-instance-role}"
INSTANCE_PROFILE_NAME="${INSTANCE_PROFILE_NAME:-${ROLE_NAME}-profile}"

if ! aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "ERROR: Role '$ROLE_NAME' does not exist." >&2
  exit 1
fi

if ! aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" >/dev/null 2>&1; then
  aws iam create-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" --tags Key=Name,Value="$INSTANCE_PROFILE_NAME" Key=${COMMON_TAG_KEY:-Project},Value="${COMMON_TAG_VALUE:-capstone-project}" >/dev/null
fi

aws iam add-role-to-instance-profile \
  --instance-profile-name "$INSTANCE_PROFILE_NAME" \
  --role-name "$ROLE_NAME" >/dev/null 2>&1 || true

echo "Associated role '$ROLE_NAME' with instance profile '$INSTANCE_PROFILE_NAME'"