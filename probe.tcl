# SimVision/Xcelium waveform probing script
# Project: CNN convolution RTL simulation
#
# Usage:
#   1. Compile/elaborate your testbench with Xcelium.
#   2. Start the simulation in the Cadence SimVision/Xcelium environment.
#   3. Source this file from the simulator Tcl console:
#        source probe.tcl
#
# This is a user-authored workflow script. It uses Cadence simulator commands;
# it does not include Cadence software or vendor-owned implementation code.
#
# Update TOP if your testbench top module has a different name.

set TOP P2tb_cnn_conv_top
set WAVE_DB waves.shm

# Create a waveform database.
database -open waves -shm -into $WAVE_DB

# Probe signals throughout the testbench hierarchy, including memories.
probe -create $TOP -depth all -all -dynamic -memories -database waves

# Run the simulation. If you prefer to control runtime manually, replace
# 'run' with a duration such as 'run 10 us' supported by your simulator.
run

# Close the waveform database after the run completes.
database -close waves

exit
