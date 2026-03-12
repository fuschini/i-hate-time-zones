#!/usr/bin/env bash
set -euo pipefail

#
# deploy-api.sh — Build and deploy the sign-manifesto Lambda function
#
# Usage: ./scripts/deploy-api.sh <environment>
#   environment: "prod" or "dev"
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - Terraform applied for the target environment (outputs must be available)
#   - Node.js and npm installed
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_DIR="${PROJECT_ROOT}/infra"
LAMBDA_DIR="${PROJECT_ROOT}/api/sign-manifesto"

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
    echo "WARNING: You are about to deploy the API to PRODUCTION."
    printf "Type 'yes' to continue: "
    read -r CONFIRM
    if [ "${CONFIRM}" != "yes" ]; then
        echo "Deployment cancelled."
        exit 0
    fi
    echo ""
fi

# --- Build ---

echo "Building Lambda..."
"${SCRIPT_DIR}/build-lambda.sh"

# --- Read Terraform outputs ---

echo "Reading Terraform outputs for '${ENVIRONMENT}'..."

cd "${INFRA_DIR}"
terraform workspace select "${ENVIRONMENT}" >/dev/null
FUNCTION_NAME=$(terraform output -raw lambda_function_name)
API_URL=$(terraform output -raw api_url)

if [ -z "${FUNCTION_NAME}" ]; then
    echo "Error: could not read Terraform outputs. Have you run 'terraform apply -var-file=${ENVIRONMENT}.tfvars'?"
    exit 1
fi

echo "  Function:  ${FUNCTION_NAME}"
echo "  API URL:   ${API_URL}"
echo ""

# --- Deploy ---

echo "Updating Lambda function code..."

cd "${LAMBDA_DIR}"
zip -j dist/lambda.zip dist/index.mjs

aws lambda update-function-code \
    --function-name "${FUNCTION_NAME}" \
    --zip-file "fileb://dist/lambda.zip" \
    --output text \
    --query 'FunctionArn'

echo ""
echo "Deploy complete!"
echo "  ${API_URL}"
