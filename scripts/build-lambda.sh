#!/usr/bin/env bash
set -euo pipefail

#
# build-lambda.sh — Bundle the sign-manifesto Lambda handler with esbuild
#
# Usage: ./scripts/build-lambda.sh
#
# Prerequisites:
#   - Node.js and npm installed
#   - Dependencies installed in api/sign-manifesto/
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LAMBDA_DIR="${PROJECT_ROOT}/api/sign-manifesto"

echo "Building sign-manifesto Lambda..."

# Install dependencies if needed
if [ ! -d "${LAMBDA_DIR}/node_modules" ]; then
    echo "Installing dependencies..."
    cd "${LAMBDA_DIR}" && npm install
fi

# Bundle with esbuild
cd "${LAMBDA_DIR}"
npx esbuild handler.ts \
    --bundle \
    --platform=node \
    --target=node20 \
    --format=esm \
    --outfile=dist/index.mjs \
    --external:@aws-sdk/client-dynamodb \
    --external:@aws-sdk/lib-dynamodb \
    --external:@aws-sdk/client-ses

echo "Build complete: api/sign-manifesto/dist/index.mjs"
