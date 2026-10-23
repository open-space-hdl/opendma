# Changelog

The notable changes of OpenDMA. The versions follow semantic versioning: 0.y.z while the core is at TRL 3, a major
version for an incompatible change of ports, generics or the register map, a minor version for a feature and a patch
version for a fix.

## [0.2.0] - 2026-10-23

Throughput: the MM2S read bursts in flight as a generic, the rates over the memory latency in the user guide, and
Open Logic 4.7.0-ft.10. Technology readiness level 3 for Direct Register Mode and Scatter/Gather Mode, unchanged.

### Added

- `Mm2sReadBursts_g` (2 to 8, default 6): the MM2S read bursts in flight, an OpenDMA extension outside the
  PG021 parameters. With the defaults MM2S sends one stream beat per clock cycle up to a memory read latency of 72
  clock cycles; 2, the behaviour of 0.1.0, reaches 8. The internal read FIFO of the read master grows with the value.

### Changed

- Open Logic 4.7.0-ft.10 (from 4.7.0-ft.8); no port, generic or register of OpenDMA changes. Its write master
  overlaps consecutive commands, so S2MM with a memory wider than the stream is faster with short chunks: for
  example 0.98 instead of 0.70 beats per clock cycle with 512 / 256 bits and 8-beat bursts (user guide section 7).

### Fixed

- Verification: the test end fails on a missing or an extra expected alert, whatever the stop limits of the test. It
  compares the alert counters of every level from WARNING to TB_FAILURE with the expected alerts and ends the
  simulation with a failure. Before, a test that had raised the TB_ERROR stop limit passed when an expected TB_ERROR
  alert did not occur: TC-PKG-10 is the only such test, and its alert occurs.
- `docs/coverage.md` of 0.1.0 gave a wrong reason for rows 265 and 305 of `odma_s2mm_write`: both are reachable and
  are now tested (TC-S2-28). The behaviour was correct.
- User guide section 7 of 0.1.0 named one waiting S2MM result as the cause of the pause at an S2MM buffer boundary
  in Scatter/Gather Mode; the cause is the window of two descriptors per channel of the engine. Section 7 now also
  gives the rates over the read latency and over the write response latency.

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
