#!/bin/bash
##############################################################################
# deploy-to-dockerhub.sh
# Purpose: Build Docker image from scripts/docker and push to Docker Hub
# Usage: ./deploy-to-dockerhub.sh --repo yourdockerhubuser/openclaw --tag v1.0
# Environment (alternative): DOCKER_USERNAME / DOCKER_PASSWORD can be exported
##############################################################################

set -euo pipefail

REPO=""
TAG="latest"
BUILD_DIR="$(cd "$(dirname "$0")/docker" && pwd)"

usage(){ cat <<EOF
Usage: $0 --repo <dockerhub-repo> [--tag <tag>] [--no-push]

Examples:
  $0 --repo youruser/openclaw --tag v1.0
  DOCKER_USERNAME=youruser DOCKER_PASSWORD=xxx $0 --repo youruser/openclaw --tag v1.0
EOF
}

NO_PUSH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2;;
    --tag) TAG="$2"; shift 2;;
    --no-push) NO_PUSH=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "--repo is required" >&2
  usage
  exit 1
fi

IMAGE="${REPO}:${TAG}"

echo "Building Docker image: $IMAGE from $BUILD_DIR"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker CLI not found. Install Docker before running this script." >&2
  exit 1
fi

pushd "$BUILD_DIR" >/dev/null

docker build -t "$IMAGE" .

popd >/dev/null

if [[ $NO_PUSH -eq 1 ]]; then
  echo "Build complete. Skipping push as requested (--no-push)."
  exit 0
fi

echo "Pushing $IMAGE to Docker Hub"

if [[ -n "${DOCKER_USERNAME:-}" && -n "${DOCKER_PASSWORD:-}" ]]; then
  echo "Logging in using DOCKER_USERNAME env var"
  echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
else
  echo "No DOCKER_USERNAME/DOCKER_PASSWORD env vars detected. You will be prompted to login interactively."
  docker login
fi

docker push "$IMAGE"

echo "Push complete: $IMAGE"

exit 0
