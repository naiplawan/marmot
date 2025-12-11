#!/bin/bash
# Build status-go for Linux
# Supports both amd64 and arm64 architectures

set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v go > /dev/null 2>&1; then
    echo "Error: Go not installed"
    echo "Install: sudo apt install golang-go"
    exit 1
fi

# Default architecture
ARCH=${1:-amd64}

echo "Building status-go for Linux..."

VERSION=$(git describe --tags --always --dirty 2> /dev/null || echo "dev")
BUILD_TIME=$(date -u '+%Y-%m-%d_%H:%M:%S')
LDFLAGS="-s -w -X main.Version=$VERSION -X main.BuildTime=$BUILD_TIME"

echo "  Version: $VERSION"
echo "  Build time: $BUILD_TIME"
echo "  Architecture: $ARCH"
echo ""

echo "  → Building for Linux $ARCH..."
GOOS=linux GOARCH=$ARCH go build -ldflags="$LDFLAGS" -trimpath -o bin/status-go-linux-$ARCH ./cmd/status

# Create a symlink for the default architecture
if [ "$ARCH" = "amd64" ]; then
    ln -sf status-go-linux-amd64 bin/status-go
fi

echo ""
echo "✓ Build complete!"
echo ""
file bin/status-go-linux-$ARCH
size_bytes=$(stat -c%s bin/status-go-linux-$ARCH 2> /dev/null || echo 0)
size_mb=$((size_bytes / 1024 / 1024))
printf "Size: %d MB (%d bytes)\n" "$size_mb" "$size_bytes"
echo ""
echo "To build for a specific architecture:"
echo "  ./scripts/build-status-linux.sh amd64  # x86_64"
echo "  ./scripts/build-status-linux.sh arm64  # ARM64"