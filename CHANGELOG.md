# Changelog

The notable changes of OpenDMA. The versions follow semantic versioning: 0.y.z while the core is at TRL 3, a major
version for an incompatible change of ports, generics or the register map, a minor version for a feature and a patch
version for a fix.

## [Unreleased]

### Changed

- Open Logic 4.7.0-ft.10 (from 4.7.0-ft.8); no port, generic or register of OpenDMA changes.

### Fixed

- `docs/coverage.md` of 0.1.0 gave a wrong reason for rows 265 and 305 of `odma_s2mm_write`: row 265 is reachable and
  is now tested (TC-S2-28); row 305 is unreachable for the reason now stated. The behaviour was correct.

## [0.1.0] - 2026-10-20

First release: Direct Register Mode and Scatter/Gather Mode of a DMA core between AXI4 memory and AXI4-Stream
peripherals with the register map, descriptor format and programming sequences of the AMD AXI DMA (PG021,
version 7.1). Technology readiness level 3 for this scope: fully verified by simulation, not yet tested on hardware.

### Features

- `odma_core` with an MM2S and an S2MM channel, each optional, the AXI4-Lite register port, the interrupt outputs and
  the reset outputs of the stream peers.
- Direct Register Mode: the register map and fields, the programming sequences of both channels, halt, soft reset,
  interrupts and their enables, the DMA errors from the response codes of the memory.
- Scatter/Gather Mode: descriptor engine with one descriptor port for both channels, tail pointer mode, cyclic mode,
  interrupt coalescing with threshold and delay timer, the errors of the engine, packets of one or several
  descriptors in both channels.
- Transfers at any byte address and of any length up to 2**`LengthWidth_g` - 1 bytes, memory widths 32 to 1024 bits,
  stream widths 8 to 1024 bits, bursts split at 4 KB and at the burst size.
- Keyhole transfers with FIXED bursts.
- S2MM throughput: the next buffer is accepted while the write responses of the one before arrive; in
  Scatter/Gather Mode the chunks follow the buffer address; low-latency write commands with equal memory and stream
  widths.
- Every buffer is a fault-tolerant Open Logic entity with SECDED ECC; error counters, status, interrupt and error
  injection in the extension register window (0x100 to 0x1FF).
- Vendor-independent VHDL-2008 on Open Logic 4.7.0-ft.8 (open-space-hdl/open-logic-ft); a register header for C
  (`sw/odma_regs.h`).

### Verification

- 1009 tests in six testbenches pass in GHDL 6.0.0 and in QuestaSim 2024.3 (time resolution 1 fs), with code
  coverage and in the optimised run without it.
- Code coverage: every statement, 675 of 676 branches; every remaining miss of branches, state machines,
  conditions and expressions is justified in `docs/coverage.md`.
- GHDL synthesis of the core in 23 configurations; 8 inconsistent configurations are rejected by the
  configuration check.

### Not included

- Control and status streams with the user application fields, the receive length in the status stream and micro
  DMA (phase c).
- Multichannel mode and the asynchronous clock configuration (not in scope).
