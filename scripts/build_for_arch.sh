#!/bin/bash
# Build script for different AMD GPU architectures
# Usage: ./scripts/build_for_arch.sh [mi300x|mi50|rx7900xt]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if ROCm is available
if [ ! -d "/opt/rocm" ]; then
    print_error "ROCm not found in /opt/rocm"
    exit 1
fi

# Determine architecture
ARCH_NAME="${1:-auto}"

if [ "$ARCH_NAME" = "auto" ]; then
    # Try to auto-detect
    if command -v rocminfo &> /dev/null; then
        GFX_ARCH=$(rocminfo | grep "Name:" | grep "gfx" | head -1 | awk '{print $2}')
        print_info "Auto-detected architecture: $GFX_ARCH"
        case "$GFX_ARCH" in
            gfx942)
                ARCH_NAME="mi300x"
                ;;
            gfx90a)
                ARCH_NAME="mi210"
                ;;
            gfx906)
                ARCH_NAME="mi50"
                ;;
            gfx1100)
                ARCH_NAME="rx7900xt"
                ;;
            *)
                print_warn "Unknown architecture $GFX_ARCH, using default settings"
                ARCH_NAME="default"
                ;;
        esac
    else
        print_warn "Cannot auto-detect, please specify architecture"
        echo "Usage: $0 [mi300x|mi50|rx7900xt]"
        exit 1
    fi
fi

# Set architecture-specific parameters
case "$ARCH_NAME" in
    mi300x)
        CMAKE_ARCH="gfx942"
        USE_WAVE32=""
        ARCH_LABEL="MI300X (gfx942)"
        ;;
    mi210)
        CMAKE_ARCH="gfx90a"
        USE_WAVE32=""
        ARCH_LABEL="MI210 (gfx90a)"
        ;;
    mi50)
        CMAKE_ARCH="gfx906"
        USE_WAVE32=""
        ARCH_LABEL="MI50 (gfx906)"
        ;;
    rx7900xt)
        CMAKE_ARCH="gfx1100"
        USE_WAVE32="-D USE_WARPSIZE_32=ON"
        ARCH_LABEL="RX 7900 XT (gfx1100)"
        ;;
    default)
        CMAKE_ARCH=""
        USE_WAVE32=""
        ARCH_LABEL="Default"
        ;;
    *)
        print_error "Unknown architecture: $ARCH_NAME"
        echo "Supported: mi300x, mi50, rx7900xt, auto"
        exit 1
        ;;
esac

print_info "Building for: $ARCH_LABEL"

# Create build directory
BUILD_DIR="$PROJECT_ROOT/build_${ARCH_NAME}"
print_info "Build directory: $BUILD_DIR"

if [ -d "$BUILD_DIR" ]; then
    print_warn "Build directory exists, cleaning..."
    rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Configure CMake
print_info "Configuring CMake..."
CMAKE_CMD="CMAKE_PREFIX_PATH=/opt/rocm/lib/cmake cmake .."
CMAKE_CMD="$CMAKE_CMD -D BUILD_BENCHMARKS=ON"
if [ -n "$CMAKE_ARCH" ]; then
    CMAKE_CMD="$CMAKE_CMD -D CMAKE_HIP_ARCHITECTURES=\"$CMAKE_ARCH\""
fi
if [ -n "$USE_WAVE32" ]; then
    CMAKE_CMD="$CMAKE_CMD $USE_WAVE32"
fi

print_info "Running: $CMAKE_CMD"
eval $CMAKE_CMD

# Build
print_info "Building..."
NPROC=$(nproc)
make -j$NPROC

# Check if build succeeded
if [ $? -eq 0 ]; then
    print_info "Build successful!"
    print_info "Benchmarks location: $BUILD_DIR/benchmarks/"
    echo ""
    echo "Available benchmarks:"
    ls -1 "$BUILD_DIR/benchmarks/" | grep "^benchmark_" || true
else
    print_error "Build failed!"
    exit 1
fi

# Create symlink to latest build
cd "$PROJECT_ROOT"
rm -f build_latest
ln -s "build_${ARCH_NAME}" build_latest
print_info "Symlink created: build_latest -> build_${ARCH_NAME}"
