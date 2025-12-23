#!/usr/bin/env python3
"""
Generate NAMD configuration files for 250 MD trajectories.
RIGOROUS equilibration + MAXIMUM PERFORMANCE OPTIMIZATIONS.
"""

import os
from pathlib import Path

# System definitions with size metadata for smart scheduling
SYSTEMS = [
    ("regime0_1RC7_300K", 300, "small"),
    ("regime0_1RC7_350K", 350, "small"),
    ("regime1_1A60_300K", 300, "small"),      # Fixed: was xlarge
    ("regime1_1A60_350K", 350, "small"),
    ("regime2_165D_300K", 300, "tiny"),
    ("regime2_165D_350K", 350, "tiny"),
    ("regime3_1K8W_300K", 300, "tiny"),
    ("regime3_1K8W_350K", 350, "tiny"),
    ("regime4_1LNG_300K", 300, "medium"),
    ("regime4_1LNG_350K", 350, "medium"),
    ("regime5_1E7K_300K", 300, "small"),
    ("regime5_1E7K_350K", 350, "small"),
    ("regime6_1KXK_300K", 300, "medium"),
    ("regime6_1KXK_350K", 350, "medium"),
    ("regime7_1IDV_300K", 300, "tiny"),      # Fixed: was small
    ("regime7_1IDV_350K", 350, "tiny"),
    ("regime8_regime8_domain_300K", 300, "xlarge"),  # Only xlarge now
    ("regime9_1DRZ_300K", 300, "medium"),
    ("regime9_1DRZ_350K", 350, "medium"),
    ("regime10_1MJI_300K", 300, "medium"),
    ("regime10_1MJI_350K", 350, "medium"),
    ("regime11_1HQ1_300K", 300, "medium"),
    ("regime11_1HQ1_350K", 350, "medium"),
    ("regime12_1KQ2_300K", 300, "tiny"),
    ("regime12_1KQ2_350K", 350, "tiny"),
]

# Simulation parameters - PERFORMANCE OPTIMIZED
N_REPLICAS = 10
SIM_LENGTH_NS = 20
TIMESTEP_FS = 2.0
OUTPUT_FREQ_PS = 10.0  # 10 ps = 2000 frames (was 2 ps = 10k frames - 5× less I/O!)

# Equilibration protocol
EQUIL_MINIMIZE_STEPS = 10000
EQUIL_HEAT_PS = 0.2
EQUIL_NVT_PS = 0.5
EQUIL_NPT_PS = 0.5

def create_namd_config(system_name, temperature, replica_id, system_size, base_dir):
    """Generate NAMD config with rigorous equilibration + performance opts."""
    
    # Calculate steps
    steps_per_ns = int(1e6 / TIMESTEP_FS)
    total_prod_steps = SIM_LENGTH_NS * steps_per_ns
    output_freq = int(OUTPUT_FREQ_PS * 1000 / TIMESTEP_FS)  # 5000 steps
    
    # Equilibration steps
    heat_steps = int(EQUIL_HEAT_PS * 1e6 / TIMESTEP_FS)
    nvt_steps = int(EQUIL_NVT_PS * 1e6 / TIMESTEP_FS)
    npt_steps = int(EQUIL_NPT_PS * 1e6 / TIMESTEP_FS)
    
    # Unique seed
    seed = 12345 + replica_id * 1000 + hash(system_name) % 1000
    
    output_name = f"{system_name}_rep{replica_id:02d}"
    
    # Performance optimizations based on size
    if system_size == "xlarge":
        pme_grid = 1.0
        pairlist = 13.0
        patch_dim = 20.0
    elif system_size == "medium":
        pme_grid = 0.9
        pairlist = 12.5
        patch_dim = 18.0
    else:  # small/tiny
        pme_grid = 0.8
        pairlist = 12.0
        patch_dim = 16.0
    
    config = f"""#############################################################
## NAMD Config: {system_name} Rep {replica_id}
## RIGOROUS + PERFORMANCE OPTIMIZED
#############################################################

#############################################################
## INPUT
#############################################################
amber yes
parmfile ../topology_files/{system_name}.prmtop
ambercoor ../topology_files/{system_name}.inpcrd
temperature {temperature}
seed {seed}

#############################################################
## OUTPUT - I/O OPTIMIZED
#############################################################
outputName {output_name}
binaryoutput yes
binaryrestart yes
restartfreq {output_freq}
dcdfreq {output_freq}
xstFreq {output_freq}
outputEnergies {output_freq * 5}
outputTiming {output_freq * 10}
flushOutput yes

#############################################################
## INTEGRATION
#############################################################
timestep {TIMESTEP_FS}
rigidBonds all
nonbondedFreq 1
fullElectFrequency 2
stepspercycle 20

#############################################################
## FORCE FIELD
#############################################################
exclude scaled1-4
1-4scaling 0.833333
switching on
switchdist 10.0
cutoff 12.0
pairlistdist {pairlist}

#############################################################
## PME - PERFORMANCE TUNED
#############################################################
PME yes
PMEGridSpacing {pme_grid}
PMEInterpOrder 6

#############################################################
## TEMPERATURE
#############################################################
langevin on
langevinDamping 1.0
langevinTemp {temperature}
langevinHydrogen off

#############################################################
## PRESSURE
#############################################################
useGroupPressure yes
useFlexibleCell no
useConstantArea no
langevinPiston on
langevinPistonTarget 1.01325
langevinPistonPeriod 100.0
langevinPistonDecay 50.0
langevinPistonTemp {temperature}

#############################################################
## PERFORMANCE OPTIMIZATIONS
#############################################################
CUDASOAintegrate on
margin 2.5
patchDimension {patch_dim}

#############################################################
## RIGOROUS EQUILIBRATION
#############################################################

print "EQUILIBRATION STAGE 1: Minimization ({EQUIL_MINIMIZE_STEPS} steps)"
minimize {EQUIL_MINIMIZE_STEPS}

print "EQUILIBRATION STAGE 2: Restrained heating to {temperature}K ({EQUIL_HEAT_PS} ns)"
constraints on
consref ../topology_files/{system_name}.inpcrd
conskfile ../topology_files/{system_name}.inpcrd
conskcol B
constraintScaling 5.0

velocity reassign {temperature * 0.5}
run {heat_steps // 2}

for {{set i 0}} {{$i < 10}} {{incr i}} {{
    set temp [expr {temperature} * 0.5 + ({temperature} * 0.5) * $i / 10.0]
    langevinTemp $temp
    langevinPistonTemp $temp
    run [expr {heat_steps} / 20]
}}

print "EQUILIBRATION STAGE 3: NVT equilibration ({EQUIL_NVT_PS} ns)"
langevinPiston off
constraintScaling 2.0
run {nvt_steps}

print "EQUILIBRATION STAGE 4: NPT equilibration ({EQUIL_NPT_PS} ns)"
langevinPiston on
constraintScaling 1.0
run {npt_steps // 2}

constraints off
run {npt_steps // 2}

#############################################################
## PRODUCTION MD
#############################################################
print "PRODUCTION: {SIM_LENGTH_NS} ns at {temperature}K"

dcdfreq {output_freq}
xstFreq {output_freq}
restartfreq {output_freq}
outputEnergies {output_freq}

run {total_prod_steps}

print "COMPLETE: {output_name}"
"""
    
    return config, system_size

def main():
    base_dir = Path(__file__).parent.parent
    config_dir = base_dir / "namd_configs"
    config_dir.mkdir(exist_ok=True)
    
    print("="*80)
    print("Generating RIGOROUS + PERFORMANCE OPTIMIZED NAMD Configs")
    print("="*80)
    print(f"Systems: {len(SYSTEMS)}")
    print(f"Replicas: {N_REPLICAS}")
    print(f"Production: {SIM_LENGTH_NS} ns")
    print(f"Equilibration: {EQUIL_HEAT_PS + EQUIL_NVT_PS + EQUIL_NPT_PS:.1f} ns")
    print(f"Output frequency: {OUTPUT_FREQ_PS} ps (I/O optimized)")
    print(f"Total trajectories: {len(SYSTEMS) * N_REPLICAS}")
    print("="*80)
    print()
    
    metadata = []
    count = 0
    
    for system_name, temperature, size in SYSTEMS:
        for replica in range(N_REPLICAS):
            config, sys_size = create_namd_config(system_name, temperature, replica, size, base_dir)
            
            config_file = config_dir / f"{system_name}_rep{replica:02d}.namd"
            with open(config_file, 'w') as f:
                f.write(config)
            
            metadata.append(f"{system_name}_rep{replica:02d}.namd\t{sys_size}\t{temperature}\n")
            
            count += 1
            if count % 50 == 0:
                print(f"Generated {count}/{len(SYSTEMS) * N_REPLICAS} configs...")
    
    # Write metadata
    with open(config_dir / "system_metadata.txt", 'w') as f:
        f.write("# config_file\tsystem_size\ttemperature\n")
        f.writelines(metadata)
    
    print(f"\n✅ Generated {count} OPTIMIZED configs")
    print(f"✅ Metadata: {config_dir}/system_metadata.txt")
    print("="*80)
    print("\nPerformance optimizations:")
    print(f"  • I/O: {OUTPUT_FREQ_PS} ps output (5× less than before)")
    print("  • Adaptive PME grid spacing by system size")
    print("  • Adaptive patch dimensions")
    print("  • CUDA SOA integration enabled")
    print("  • Binary restart for fast recovery")
    print("="*80)

if __name__ == "__main__":
    main()
