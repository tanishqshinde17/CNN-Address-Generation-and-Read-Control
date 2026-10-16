# Assignment 3 — CNN Address Generation and Read Control

**Course:** Advanced RTL Modeling & Verification-Driven Design  
**Program:** IIT Kharagpur — AI-Enabled VLSI Design

## Objective

Design and simulate an address-generation and read-control block for the first layer of a CNN using four staggered SRAM banks.

## Specifications

- Input image: 256 × 256 pixels
- Pixel width: 8 bits
- SRAM banks: 4
- Bank organization: 256 × 64 bytes per bank
- Output bus: 24 bits
- Bank mapping: global column index modulo 4

## Files

- `cnn_addr_gen.sv` — RTL implementation
- `tb_cnn_addr_gen.sv` — SystemVerilog testbench
- `assignment3.log` — Simulation log, if included

## Simulation

The design was simulated using Cadence Xcelium.

```bash
xrun -64bit -sv -access +rwc cnn_addr_gen.sv tb_cnn_addr_gen.sv -top tb_cnn_addr_gen -l cnn_addr_gen.log
```

## Verification Results

The implemented testbench checks five bank-mapping positions and verifies controller scan completion.

**Note:** These tests do not constitute exhaustive pixel-level verification across the complete image.

## Memory Addressing Assumption

Each bank stores 256 rows × 64 bytes. The RTL therefore uses a 14-bit local byte address to address 16,384 locations per bank. Confirm the expected address-port width against the instructor's required interface.
