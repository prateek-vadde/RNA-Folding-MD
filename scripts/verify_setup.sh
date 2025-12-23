#!/bin/bash
#############################################################
## Pre-flight verification script
## Checks all requirements before launching MD
#############################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=============================================================================="
echo "RNA Folding MD - Setup Verification"
echo "=============================================================================="
echo ""

ERRORS=0

# Check 1: NAMD binary
echo "[1/7] Checking NAMD binary..."
if [ -z "$NAMD_BIN" ]; then
    NAMD_BIN="namd3"
fi

if command -v $NAMD_BIN &> /dev/null; then
    NAMD_PATH=$(which $NAMD_BIN)
    echo "  ✅ NAMD found: $NAMD_PATH"
    
    # Try to get version
    $NAMD_BIN 2>&1 | grep -i "version\|namd" | head -3 || true
else
    echo "  ❌ NAMD not found. Set NAMD_BIN environment variable."
    echo "     Example: export NAMD_BIN=/path/to/namd3"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 2: Topology files
echo "[2/7] Checking topology files..."
PRMTOP_COUNT=$(find "$BASE_DIR/topology_files" -name "*.prmtop" 2>/dev/null | wc -l)
INPCRD_COUNT=$(find "$BASE_DIR/topology_files" -name "*.inpcrd" 2>/dev/null | wc -l)

if [ $PRMTOP_COUNT -eq 25 ] && [ $INPCRD_COUNT -eq 25 ]; then
    echo "  ✅ All 25 topology file pairs found"
    TOPO_SIZE=$(du -sh "$BASE_DIR/topology_files" | cut -f1)
    echo "     Total size: $TOPO_SIZE"
else
    echo "  ❌ Missing topology files (found $PRMTOP_COUNT prmtop, $INPCRD_COUNT inpcrd, need 25 each)"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 3: NAMD configs
echo "[3/7] Checking NAMD configurations..."
if [ -d "$BASE_DIR/namd_configs" ]; then
    CONFIG_COUNT=$(find "$BASE_DIR/namd_configs" -name "*.namd" 2>/dev/null | wc -l)
    if [ $CONFIG_COUNT -eq 250 ]; then
        echo "  ✅ All 250 NAMD configs found"
    elif [ $CONFIG_COUNT -eq 0 ]; then
        echo "  ⚠️  No NAMD configs found. Run: ./generate_namd_configs.py"
    else
        echo "  ⚠️  Found $CONFIG_COUNT configs (expected 250)"
        echo "     Re-run: ./generate_namd_configs.py"
    fi
else
    echo "  ⚠️  namd_configs directory not found. Run: ./generate_namd_configs.py"
fi
echo ""

# Check 4: GPU availability
echo "[4/7] Checking GPU availability..."
if command -v nvidia-smi &> /dev/null; then
    GPU_COUNT=$(nvidia-smi --list-gpus 2>/dev/null | wc -l)
    echo "  ✅ nvidia-smi found, $GPU_COUNT GPU(s) detected"
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | nl -v 0 -w 1 -s ': ' || true
    
    if [ $GPU_COUNT -lt 2 ]; then
        echo "  ⚠️  Only $GPU_COUNT GPU detected (expected 2× B200)"
    fi
else
    echo "  ❌ nvidia-smi not found. CUDA not properly installed?"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 5: CUDA version
echo "[5/7] Checking CUDA version..."
if command -v nvcc &> /dev/null; then
    CUDA_VERSION=$(nvcc --version | grep -oP 'release \K[0-9.]+' || echo "unknown")
    echo "  ✅ CUDA version: $CUDA_VERSION"
    
    if [[ ! "$CUDA_VERSION" =~ ^12\.[6-9] ]] && [[ ! "$CUDA_VERSION" =~ ^1[3-9]\. ]]; then
        echo "  ⚠️  CUDA 12.6+ recommended for B200 support (found $CUDA_VERSION)"
    fi
else
    echo "  ⚠️  nvcc not found. CUDA may not be in PATH"
fi
echo ""

# Check 6: Disk space
echo "[6/7] Checking disk space..."
OUTPUT_DIR="${OUTPUT_DIR:-$BASE_DIR/output}"
mkdir -p "$OUTPUT_DIR"

AVAIL_GB=$(df -BG "$OUTPUT_DIR" | tail -1 | awk '{print $4}' | sed 's/G//')
REQUIRED_GB=500  # ~2 GB per trajectory × 250 trajectories

if [ $AVAIL_GB -gt $REQUIRED_GB ]; then
    echo "  ✅ Sufficient disk space: ${AVAIL_GB}G available (need ~${REQUIRED_GB}G)"
else
    echo "  ⚠️  Low disk space: ${AVAIL_GB}G available (recommend ${REQUIRED_GB}G)"
    echo "     Consider using local NVMe: export OUTPUT_DIR=/path/to/fast/storage"
fi
echo ""

# Check 7: GNU parallel (optional)
echo "[7/7] Checking GNU parallel (optional)..."
if command -v parallel &> /dev/null; then
    PARALLEL_VERSION=$(parallel --version 2>/dev/null | head -1 || echo "unknown")
    echo "  ✅ GNU parallel found: $PARALLEL_VERSION"
    echo "     Will use optimal load balancing"
else
    echo "  ⚠️  GNU parallel not found (optional)"
    echo "     Install for better performance: conda install -c conda-forge parallel"
    echo "     Script will fall back to sequential execution"
fi
echo ""

# Summary
echo "=============================================================================="
if [ $ERRORS -eq 0 ]; then
    echo "✅ All critical checks passed!"
    echo ""
    echo "Next steps:"
    echo "  1. Generate configs (if not done): ./generate_namd_configs.py"
    echo "  2. Launch MD: ./launch_md_dual_b200.sh"
    echo "  3. Monitor: watch -n 10 'ls $OUTPUT_DIR/*.dcd | wc -l'"
else
    echo "❌ $ERRORS critical errors found. Fix before proceeding."
fi
echo "=============================================================================="

exit $ERRORS
