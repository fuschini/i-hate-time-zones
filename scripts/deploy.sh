#!/usr/bin/env bash
set -euo pipefail

#
# deploy.sh — Deploy the ihatetimezones.com static site to S3 + CloudFront
#
# Usage: ./scripts/deploy.sh <environment>
#   environment: "prod" or "dev"
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - Terraform applied for the target environment (outputs must be available)
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_DIR="${PROJECT_ROOT}/infra"
SITE_DIR="${PROJECT_ROOT}/site"

# --- Validate arguments ---

if [ $# -ne 1 ]; then
    echo "Usage: $0 <environment>"
    echo "  environment: prod | dev"
    exit 1
fi

ENVIRONMENT="$1"

if [ "${ENVIRONMENT}" != "prod" ] && [ "${ENVIRONMENT}" != "dev" ]; then
    echo "Error: environment must be 'prod' or 'dev', got '${ENVIRONMENT}'"
    exit 1
fi

# --- Safety check for prod ---

if [ "${ENVIRONMENT}" = "prod" ]; then
    echo ""
    echo "WARNING: You are about to deploy to PRODUCTION (ihatetimezones.com)."
    printf "Type 'yes' to continue: "
    read -r CONFIRM
    if [ "${CONFIRM}" != "yes" ]; then
        echo "Deployment cancelled."
        exit 0
    fi
    echo ""
fi

# --- Read Terraform outputs ---

echo "Reading Terraform outputs for '${ENVIRONMENT}'..."

cd "${INFRA_DIR}"
S3_BUCKET=$(terraform output -raw s3_bucket_name)
CF_DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id)
SITE_URL=$(terraform output -raw site_url)

if [ -z "${S3_BUCKET}" ] || [ -z "${CF_DISTRIBUTION_ID}" ]; then
    echo "Error: could not read Terraform outputs. Have you run 'terraform apply -var-file=${ENVIRONMENT}.tfvars'?"
    exit 1
fi

echo "  S3 bucket:       ${S3_BUCKET}"
echo "  CloudFront dist: ${CF_DISTRIBUTION_ID}"
echo "  Site URL:        ${SITE_URL}"
echo ""

# --- Sync files to S3 ---

echo "Syncing site files to s3://${S3_BUCKET}/ ..."

# HTML files: 24-hour cache
aws s3 sync "${SITE_DIR}/" "s3://${S3_BUCKET}/" \
    --delete \
    --exclude "*" \
    --include "*.html" \
    --cache-control "max-age=86400" \
    --content-type "text/html"

# Everything else (CSS, JS, images): 7-day cache
aws s3 sync "${SITE_DIR}/" "s3://${S3_BUCKET}/" \
    --delete \
    --exclude "*.html" \
    --cache-control "max-age=604800"

echo "Sync complete."

# --- Invalidate CloudFront cache ---

echo "Creating CloudFront invalidation..."
INVALIDATION_ID=$(aws cloudfront create-invalidation \
    --distribution-id "${CF_DISTRIBUTION_ID}" \
    --paths "/*" \
    --query 'Invalidation.Id' \
    --output text)

echo "Invalidation created: ${INVALIDATION_ID}"

# --- Done ---

echo ""
echo "Deploy complete!"
echo "  ${SITE_URL}"
echo ""
echo "Note: CloudFront invalidation may take a few minutes to propagate."
