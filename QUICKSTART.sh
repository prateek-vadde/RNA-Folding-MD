#!/bin/bash
################################################################################
## Quick Start Script for MD_Portable on B200 System
## Run this after extracting the package
################################################################################

echo "=============================================================================="
echo "RNA Folding MD - Quick Start Setup"
echo "=============================================================================="
echo ""

# Check if NAMD_BIN is set
if [ -z "$NAMD_BIN" ]; then
    echo "⚠️  NAMD_BIN not set."
    echo ""
    echo "Please set the path to your NAMD binary:"
    echo "  export NAMD_BIN=/path/to/namd3"
    echo ""
    read -p "Enter NAMD path now (or press Enter to skip): " namd_path
    
    if [ -n "$namd_path" ]; then
        export NAMD_BIN="$namd_path"
        echo "export NAMD_BIN=$namd_path" >> ~/.bashrc
        echo "✅ NAMD_BIN set and saved to ~/.bashrc"
    else
        echo "Skipping NAMD setup. Set manually before running simulations."
    fi
fi

echo ""
echo "Running setup verification..."
echo ""

cd scripts
./verify_setup.sh

if [ $? -eq 0 ]; then
    echo ""
    echo "=============================================================================="
    echo "✅ Setup complete! Ready to run MD simulations."
    echo "=============================================================================="
    echo ""
    echo "To launch MD simulations:"
    echo "  cd scripts"
    echo "  ./launch_md_dual_b200.sh"
    echo ""
    echo "Expected runtime: ~10 hours on 2× B200 GPUs"
    echo "Total simulation time: 5.0 µs (250 trajectories × 20 ns)"
    echo "=============================================================================="
else
    echo ""
    echo "=============================================================================="
    echo "❌ Setup verification failed. Please fix errors above."
    echo "=============================================================================="
fi
