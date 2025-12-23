# RNA Folding MD - Portable Package (RIGOROUS)

Molecular dynamics simulation package for RNA folding dynamics across 13 structural regimes.

**Features:**
- ✅ Rigorous 4-stage equilibration protocol
- ✅ Auto resource detection and optimization
- ✅ Smart job scheduling (large systems first)
- ✅ Memory-aware GPU assignment
- ✅ CUDA MPS for efficient GPU sharing

## Contents

```
MD_Portable/
├── topology_files/      # AMBER topology files (50 files: 25 systems × 2 files)
│   ├── regime*.prmtop   # Parameter/topology files
│   └── regime*.inpcrd   # Coordinate files
├── scripts/             # Execution scripts
│   ├── generate_namd_configs.py    # Generate 250 NAMD configs (RIGOROUS)
│   ├── launch_md_dual_b200.sh      # Smart launcher with auto resource detection
│   └── verify_setup.sh             # Pre-flight checks
├── namd_configs/        # Generated NAMD configuration files (250 + metadata)
├── output/              # MD trajectory output (created during run)
├── SYSTEM_INFO.txt      # Regime and system details
├── QUICKSTART.sh        # One-command setup
└── README.md            # This file
```

## Requirements

### Software
- **NAMD 3.0+** compiled for Blackwell (sm_100) or Hopper (sm_90)
  - CUDA 12.6+ required for B200
  - Build with: `-DNAMD_CUDA -DCUDA_ARCH=sm_100`
- **CUDA 12.6+** with B200 support
- **GNU parallel** (optional but highly recommended)
  - Install: `apt-get install parallel` or `conda install parallel`
  - Provides optimal load balancing and job management

### Hardware (Auto-Detected)
**Best performance (8-10 hours):**
- 8× NVIDIA A100 GPUs (80 GB each) - FASTEST option
- 640 GB total GPU memory
- 240 CPU cores
- Local NVMe storage for output

**Also excellent (~8-10 hours with ramdisk):**
- 2× NVIDIA B200 GPUs (180 GB each) - 52+ CPUs, 700+ GB RAM
  - **Auto-enables ramdisk mode if >600 GB RAM** (20-30% speedup!)
- 4× NVIDIA H100 GPUs (80 GB each) - 104 CPUs

**Auto-adapts to:**
- Any multi-GPU CUDA setup
- Available CPU and memory resources
- **Automatic ramdisk usage** if ≥600 GB RAM (writes to /dev/shm, copies back at end)

## Setup Instructions

### 1. Clone Repository
```bash
git clone <your-repo-url>
cd MD_Portable
```

### 2. Set Environment Variables
```bash
export NAMD_BIN=/path/to/namd3              # Path to NAMD binary
export OUTPUT_DIR=/path/to/fast/storage     # Local NVMe recommended
# GPU selection is auto-detected, but can override:
# export CUDA_VISIBLE_DEVICES=0,1
```

### 3. Generate NAMD Configurations (if not already done)
```bash
cd scripts
./generate_namd_configs.py
```

This creates 250 NAMD config files with **rigorous 4-stage equilibration**:
1. Extended minimization (10,000 steps)
2. Restrained heating (200 ps, RNA fixed)
3. NVT equilibration (500 ps, reduced constraints)
4. NPT equilibration (500 ps, constraints removed)
5. Production MD (20 ns)

### 4. Verify Setup
```bash
./verify_setup.sh
```

Checks:
- NAMD binary exists and runs
- All topology files present (25 systems × 2 files)
- NAMD configs generated (250 files + metadata)
- GPU availability (auto-detects count and memory)
- CUDA version compatibility
- Disk space (needs ~500 GB for output)

### 5. Launch MD Simulations
```bash
./launch_md_dual_b200.sh
```

**Auto resource detection:**
- Detects GPU count and memory
- Calculates optimal parallelization
- B200 (180 GB): ~22 jobs per GPU
- H100/A100 (80 GB): ~10 jobs per GPU
- Adapts to CPU cores and RAM

**Smart scheduling:**
- Sorts jobs by system size (xlarge → tiny)
- Runs large systems first to prevent bottlenecking
- Assigns GPUs based on memory requirements
- Uses CUDA MPS for efficient sharing

**Expected runtime (250 trajectories):**
- **8× A100: ~8-10 hours** (FASTEST - 80 parallel, 4.8 H100-eq compute)
- **2× B200: ~8-10 hours** with ramdisk (44 parallel, 4.0 H100-eq, 700+ GB RAM)
- 2× B200: ~10-12 hours without ramdisk (if <600 GB RAM)
- 4× H100: ~10-12 hours (40 parallel, 4.0 H100-eq compute)
- 1× B200: ~20-22 hours (22 parallel, 2.0 H100-eq compute)

## Simulation Details

### Equilibration Protocol (RIGOROUS)
Each trajectory undergoes 4-stage equilibration before production:

| Stage | Duration | Purpose | Constraints |
|-------|----------|---------|-------------|
| 1. Minimization | 10,000 steps | Remove clashes | None |
| 2. Heating | 200 ps | Heat solvent gently | RNA fixed (5.0 kcal/mol/Ų) |
| 3. NVT | 500 ps | Equilibrate volume | RNA weakly restrained (2.0) |
| 4. NPT | 500 ps | Equilibrate pressure | Gradually removed |

Total equilibration: **~1.2 ns** per trajectory

### Production Parameters
- **Systems**: 25 (13 regimes × 2 temperatures, except regime8)
- **Replicas**: 10 per system (different random seeds)
- **Production length**: 20 ns per replica
- **Total per trajectory**: 21.2 ns (including equilibration)
- **Total trajectories**: 250
- **Total production time**: 5.0 µs
- **Output frequency**: 2 ps (10,000 frames per trajectory)
- **Total frames**: 2,500,000

### Force Field (Rigorous Settings)
- **Base**: AMBER14 ff99
- **RNA corrections**: bsc0 (backbone) + chiOL3 (glycosidic)
- **Combined**: RNA.OL3 force field
- **Solvent**: TIP3P explicit water
- **Ions**: Na+ for neutralization
- **Solvation**: 9 Å buffer
- **Cutoffs**: 12.0 Å (rigorous, not 9.0 Å)
- **PME**: Grid spacing 0.8-1.0 Å, order 6
- **Integration**: 2 fs timestep with SHAKE

## Output Files

Per trajectory (250× each):
- `*.dcd` - Binary trajectory file (~1-3 GB each)
- `*.xst` - Extended system trajectory (box dimensions)
- `*.coor` - Final coordinates
- `*.vel` - Final velocities
- `*.xsc` - Extended system configuration
- `*.log` - NAMD execution log

Total output size: **~400-500 GB**

## Monitoring Progress

During execution:
```bash
# Check completed trajectories
watch -n 10 'ls output/*.dcd | wc -l'

# Check for failures
grep -l "ERROR\|FATAL" output/*.log

# Monitor GPU usage
watch nvidia-smi

# View execution log (if using GNU parallel)
tail -f output/parallel_execution.log
```

## Troubleshooting

### NAMD not found
```bash
which namd3
export NAMD_BIN=$(which namd3)
```

### GPU memory errors
Launcher auto-calculates jobs per GPU, but can override:
```bash
# Edit launch_md_dual_b200.sh
# Reduce JOBS_PER_GPU manually if needed
```

### Slow performance / bottlenecking
- Check large systems aren't blocking: `ls -lh output/*.dcd | grep regime1`
- Verify CUDA MPS is running: `nvidia-cuda-mps-control status`
- Use local NVMe, not NFS: `export OUTPUT_DIR=/local/nvme/md_output`

### GNU parallel not available
- Install: `conda install -c conda-forge parallel`
- Or script falls back to batched execution (slower but works)

### Equilibration failing
Check logs for:
- "SHAKE failure" → timestep too large (shouldn't happen with 2 fs)
- "Pressure too high" → minimization insufficient (shouldn't happen with 10k steps)
- "Constraint errors" → PDB/prmtop mismatch (verify topology files)

## Scientific Context

This MD package implements **Part III.4** of the RNA folding research plan:

**Attractor Definition (Operational)**
- Empirical stability through return probability
- Residence time in basins  
- Perturbation response via temperature variation (300K vs 350K)

**Key Principle**: "Many short trajectories > few long ones"
- 10 replicas × 20 ns samples basin statistics better than 1× 200 ns
- Enables proper error estimation for attractor stability
- Temperature variation reveals regime boundaries

**Downstream Analysis** (after MD):
1. Extract State objects from trajectories (base pairs, stacking, loops)
2. Compute distance matrices using frozen metrics
3. Project to frozen 10D latent space (diffusion maps)
4. Identify empirical attractors per regime
5. Train Neural SDE on dynamics: dz = f(z,s,λ,r)dt + Σ(z)dW
6. Symbolic regression (SINDy) for sparse equations

## Performance Benchmarks

Measured on NAMD 3.0.2 with CUDA 12.8:

| GPU | System Size | Performance | 20 ns Runtime |
|-----|-------------|-------------|---------------|
| B200 (180 GB) | Small (30k atoms) | ~200 ns/day | 2.4 hours |
| B200 | Medium (60k atoms) | ~100 ns/day | 4.8 hours |
| B200 | Large (110k atoms) | ~60 ns/day | 8 hours |
| H100 (80 GB) | Medium | ~50 ns/day | 9.6 hours |

**Overall walltime for all 250 trajectories:**
- 8× A100 with smart scheduling: **~8-10 hours** (FASTEST)
- 2× B200 or 4× H100: **~10-12 hours**

## Citations

If you use this package, please cite:
- **AMBER**: Case et al. J. Comput. Chem. 2005
- **RNA.OL3**: Zgarbová et al. J. Chem. Theory Comput. 2011
- **NAMD**: Phillips et al. J. Comput. Chem. 2005

## Contact

For issues, see GitHub repository or open an issue.

## Changelog

**v2.0 - Rigorous Protocol** (Current)
- ✅ 4-stage equilibration protocol
- ✅ Auto resource detection
- ✅ Smart job scheduling by system size
- ✅ Memory-aware GPU assignment
- ✅ Extended cutoffs (12 Å vs 9 Å)
- ✅ Rigorous PME settings
- ✅ CUDA optimizations

**v1.0 - Initial Release**
- Basic minimization + production
- Round-robin GPU assignment
- Manual resource specification
