#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Terraform remote state bootstrap
#
# Run ONCE before the first `terraform init`.
# Idempotent — safe to re-run; existing resources are skipped.
#
# Usage:
#   ./scripts/bootstrap-tf-state.sh [region]
#
# After this script completes it prints the exact backend "s3" block to paste
# into main.tf (replacing the ACCOUNT_ID placeholder). Then run:
#   terraform init -migrate-state
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REGION="${1:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="bookstore-terraform-state-${ACCOUNT_ID}"
TABLE="terraform-state-lock"

echo "Account : ${ACCOUNT_ID}"
echo "Region  : ${REGION}"
echo "Bucket  : ${BUCKET}"
echo "Table   : ${TABLE}"
echo ""

# ── S3 bucket ──────────────────────────────────────────────────────────────
if aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  echo "[skip] Bucket already exists."
else
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket \
      --bucket "${BUCKET}" \
      --region "${REGION}"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET}" \
      --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}"
  fi

  aws s3api put-bucket-versioning \
    --bucket "${BUCKET}" \
    --versioning-configuration Status=Enabled

  aws s3api put-bucket-encryption \
    --bucket "${BUCKET}" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'

  aws s3api put-public-access-block \
    --bucket "${BUCKET}" \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

  echo "[ok] Bucket created and hardened."
fi

# ── DynamoDB lock table ────────────────────────────────────────────────────
if aws dynamodb describe-table \
     --table-name "${TABLE}" \
     --region "${REGION}" \
     --query "Table.TableName" \
     --output text 2>/dev/null | grep -q "${TABLE}"; then
  echo "[skip] DynamoDB table already exists."
else
  aws dynamodb create-table \
    --table-name "${TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}"
  echo "[ok] DynamoDB table created."
fi

# ── Print backend block to paste into main.tf ─────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Bootstrap complete. Replace the ACCOUNT_ID placeholder in main.tf"
echo "backend block with the values below, then run: terraform init -migrate-state"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo '  backend "s3" {'
echo "    bucket         = \"${BUCKET}\""
echo '    key            = "prod/terraform.tfstate"'
echo "    region         = \"${REGION}\""
echo "    dynamodb_table = \"${TABLE}\""
echo '    encrypt        = true'
echo '  }'
echo ""
