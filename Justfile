set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    just --list

# Build the Docker image for amd64
build-amd64:
    docker buildx build --platform linux/amd64 -t "${IMAGE:-ubuntu-env:latest}" --load .

# Build the Docker image for arm64
build-arm64:
    docker buildx build --platform linux/arm64 -t "${IMAGE:-ubuntu-env:latest}" --load .