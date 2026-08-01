#!/usr/bin/env bash
# One-time setup: create the private, versioned S3 bucket that holds the
# Terraform state (kept out of the repo, which is public), write
# terraform/backend.hcl pointing at it, and run terraform init.
#
# Usage: scripts/bootstrap-state.sh [bucket-name]
set -euo pipefail

cd "$(dirname "$0")/../terraform"

REGION="${AWS_REGION:-$(aws configure get region)}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="${1:-imap-scrub-tfstate-${ACCOUNT_ID}}"

if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    echo "State bucket s3://${BUCKET} already exists"
else
    if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
    else
        aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
            --create-bucket-configuration "LocationConstraint=${REGION}"
    fi
    aws s3api put-bucket-versioning --bucket "$BUCKET" \
        --versioning-configuration Status=Enabled
    aws s3api put-public-access-block --bucket "$BUCKET" \
        --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    echo "Created state bucket s3://${BUCKET}"
fi

cat > backend.hcl <<EOF
bucket       = "${BUCKET}"
key          = "imap-scrub/terraform.tfstate"
region       = "${REGION}"
use_lockfile = true
encrypt      = true
EOF

terraform init -backend-config=backend.hcl
