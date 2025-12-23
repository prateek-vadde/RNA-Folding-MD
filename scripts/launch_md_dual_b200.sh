#!/bin/bash
################################################################################
## MAXIMUM PERFORMANCE MD LAUNCHER
## Auto resource detection + CPU pinning + Smart I/O + Optimal batching
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../namd_configs"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/../output}"
TOPOLOGY_DIR="$SCRIPT_DIR/../topology_files"

NAMD_BIN="${NAMD_BIN:-namd3}"

detect_resources() {
    echo "=============================================================================="
    echo "Auto-Detecting System Resources"
    echo "=============================================================================="
    
    # GPUs
    if command -v nvidia-smi &> /dev/null; then
        GPU_COUNT=$(nvidia-smi --list-gpus | wc -l)
        GPU_MEM_TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
        GPU_NAMES=$(nvidia-smi --query-gpu=name --format=csv,noheader | paste -sd, -)
        echo "✅ GPUs: $GPU_COUNT ($GPU_NAMES)"
        echo "   Memory per GPU: ${GPU_MEM_TOTAL} MB"
    else
        echo "❌ No GPUs detected"
        exit 1
    fi
    
    # CPUs
    CPU_COUNT=$(nproc 2>/dev/null || echo 8)
    echo "✅ CPU cores: $CPU_COUNT"
    
    # RAM
    if [ -f /proc/meminfo ]; then
        RAM_TOTAL_GB=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
        echo "✅ RAM: ${RAM_TOTAL_GB} GB"
    else
        RAM_TOTAL_GB=256
    fi
    
    echo "=============================================================================="
}

calculate_parallel_jobs() {
    local gpu_mem_gb=$((GPU_MEM_TOTAL / 1024))
    
    # Conservative estimates
    if [ $gpu_mem_gb -ge 160 ]; then
        JOBS_PER_GPU=22  # B200
    elif [ $gpu_mem_gb -ge 80 ]; then
        JOBS_PER_GPU=10  # H100
    elif [ $gpu_mem_gb -ge 40 ]; then
        JOBS_PER_GPU=5   # A100
    else
        JOBS_PER_GPU=3
    fi
    
    MAX_PARALLEL=$((GPU_COUNT * JOBS_PER_GPU))
    
    # CPU limit (reserve some for system)
    local cpu_limit=$((CPU_COUNT * 9 / 10))
    if [ $MAX_PARALLEL -gt $cpu_limit ]; then
        MAX_PARALLEL=$cpu_limit
    fi
    
    echo "Parallel configuration:"
    echo "  Jobs per GPU: $JOBS_PER_GPU"
    echo "  Total parallel: $MAX_PARALLEL"
}

main() {
    detect_resources
    calculate_parallel_jobs
    
    # Verify NAMD
    if ! command -v $NAMD_BIN &> /dev/null; then
        echo "❌ NAMD not found: $NAMD_BIN"
        exit 1
    fi
    
    echo ""
    mkdir -p "$OUTPUT_DIR"
    
    # Get metadata and SORT by size (xlarge first!)
    METADATA_FILE="$CONFIG_DIR/system_metadata.txt"
    if [ ! -f "$METADATA_FILE" ]; then
        echo "❌ Metadata not found: $METADATA_FILE"
        exit 1
    fi
    
    # Sort: xlarge → medium → small → tiny
    SORTED_CONFIGS=$(mktemp)
    grep -v "^#" "$METADATA_FILE" | \
        awk '{
            if ($2=="xlarge") print "1\t"$0;
            else if ($2=="medium") print "2\t"$0;
            else if ($2=="small") print "3\t"$0;
            else print "4\t"$0;
        }' | sort -n | cut -f2- > "$SORTED_CONFIGS"
    
    TOTAL_JOBS=$(wc -l < "$SORTED_CONFIGS")
    
    echo "=============================================================================="
    echo "RNA Folding MD - MAXIMUM PERFORMANCE LAUNCHER"
    echo "=============================================================================="
    echo "Total trajectories: $TOTAL_JOBS"
    echo "Max parallel: $MAX_PARALLEL"
    echo "Strategy: Large systems first + CPU pinning + I/O optimized"
    echo "=============================================================================="
    echo ""
    
    # CUDA MPS setup
    echo "Setting up CUDA MPS..."
    export CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps
    export CUDA_MPS_LOG_DIRECTORY=/tmp/nvidia-log
    mkdir -p $CUDA_MPS_PIPE_DIRECTORY $CUDA_MPS_LOG_DIRECTORY
    
    for gpu in $(seq 0 $((GPU_COUNT - 1))); do
        CUDA_VISIBLE_DEVICES=$gpu nvidia-cuda-mps-control -d 2>/dev/null || true
    done
    
    echo "✅ CUDA MPS enabled"
    echo ""
    
    # Job execution with CPU pinning
    export NAMD_BIN OUTPUT_DIR CONFIG_DIR GPU_COUNT CPU_COUNT
    
    run_namd_job() {
        local line=$1
        local job_id=$2
        local total=$3
        
        local config_file=$(echo "$line" | cut -f1)
        local size=$(echo "$line" | cut -f2)
        
        # Smart GPU assignment
        if [ "$size" = "xlarge" ]; then
            local gpu=$(( (job_id / 3) % GPU_COUNT ))  # Less concurrency for xlarge
        else
            local gpu=$(( job_id % GPU_COUNT ))
        fi
        
        # CPU pinning (distribute across cores)
        local cores_per_job=$((CPU_COUNT / MAX_PARALLEL))
        if [ $cores_per_job -lt 1 ]; then cores_per_job=1; fi
        local start_core=$(( (job_id * cores_per_job) % CPU_COUNT ))
        local end_core=$(( start_core + cores_per_job - 1 ))
        
        local basename=$(basename "$config_file" .namd)
        local log="${OUTPUT_DIR}/${basename}.log"
        local config_path="${CONFIG_DIR}/${config_file}"
        
        echo "[$(date '+%H:%M:%S')] [$job_id/$total] $basename (${size}) → GPU$gpu cores$start_core-$end_core"
        
        cd "$OUTPUT_DIR"
        
        # Run with CPU pinning and GPU assignment
        taskset -c $start_core-$end_core \
            env CUDA_VISIBLE_DEVICES=$gpu \
            $NAMD_BIN "$config_path" > "$log" 2>&1
        
        if [ $? -eq 0 ] && grep -q "COMPLETE" "$log"; then
            echo "[$(date '+%H:%M:%S')] ✅ [$job_id/$total] $basename"
            return 0
        else
            echo "[$(date '+%H:%M:%S')] ❌ [$job_id/$total] $basename"
            return 1
        fi
    }
    
    export -f run_namd_job
    
    START_TIME=$(date +%s)
    
    if command -v parallel &> /dev/null; then
        echo "Using GNU parallel for optimal load balancing..."
        echo ""
        
        cat "$SORTED_CONFIGS" | \
            parallel -j $MAX_PARALLEL \
                     --line-buffer \
                     --tagstring "[Job {#}]" \
                     --joblog "${OUTPUT_DIR}/parallel_execution.log" \
                     run_namd_job {} {#} $TOTAL_JOBS
        
        EXIT_CODE=$?
    else
        echo "Using batched execution (install GNU parallel for better performance)"
        echo ""
        
        job_num=1
        while IFS= read -r line; do
            run_namd_job "$line" $job_num $TOTAL_JOBS &
            
            if [ $(jobs -r | wc -l) -ge $MAX_PARALLEL ]; then
                wait -n
            fi
            
            job_num=$((job_num + 1))
        done < "$SORTED_CONFIGS"
        
        wait
        EXIT_CODE=$?
    fi
    
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    HOURS=$((ELAPSED / 3600))
    MINS=$(((ELAPSED % 3600) / 60))
    
    rm -f "$SORTED_CONFIGS"
    nvidia-cuda-mps-control quit 2>/dev/null || true
    
    echo ""
    echo "=============================================================================="
    echo "Execution Summary"
    echo "=============================================================================="
    echo "Walltime: ${HOURS}h ${MINS}m"
    echo "Completed: $(find "$OUTPUT_DIR" -name "*.dcd" | wc -l)/$TOTAL_JOBS"
    echo "Failed: $(grep -l "ERROR\|FATAL" "$OUTPUT_DIR"/*.log 2>/dev/null | wc -l)"
    echo "Output: $OUTPUT_DIR"
    echo "=============================================================================="
    
    exit $EXIT_CODE
}

main "$@"
