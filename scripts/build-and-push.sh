#!/usr/bin/env bash
# Build the image and push it to the ECR repository created by terraform/.
# Usage: [PLATFORM=linux/arm64] [TAG=latest] [NAME=imap-scrub] scripts/build-and-push.sh
set -euo pipefail

cd "$(dirname "$0")/.."

NAME="${NAME:-imap-scrub}"
TAG="${TAG:-latest}"
# Must match the cpu_architecture terraform variable (ARM64 -> linux/arm64)
PLATFORM="${PLATFORM:-linux/arm64}"

REGION="${AWS_REGION:-$(aws configure get region)}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

aws ecr get-login-password --region "$REGION" |
    docker login --username AWS --password-stdin "$REGISTRY"

docker buildx build --platform "$PLATFORM" -t "${REGISTRY}/${NAME}:${TAG}" --push .

echo "Pushed ${REGISTRY}/${NAME}:${TAG} (${PLATFORM})"
