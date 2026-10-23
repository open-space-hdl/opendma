# OpenDMA Roadmap

This page tracks the development phases and the state of every module. A module is done when its verification report
is written and its regression is green.

## Technology readiness

The core is at **TRL 3** for the phases a and b: fully verified by simulation. Direct Register Mode and Scatter/Gather
Mode pass every test in GHDL and in QuestaSim, with and without code coverage; code coverage is closed or justified
([coverage](coverage.md)). The core is not tested on hardware and has no flight heritage. The
[TRL page](https://openspacehdl.org/trl/) explains what the levels mean for an IP core.

| Next level | What is needed | State |
| --- | --- | --- |
| TRL 3 of phase c | The control and status streams implemented and fully verified by simulation (GHDL and QuestaSim, code coverage closed), traceability matrix complete | Open |
| TRL 4 | Synthesis and timing closure on a target FPGA; hardware test with the drivers of a processor system; hardware test plan and test report | Open |

## Development phases

| Phase | Content | State |
| --- | --- | --- |
| a | Direct Register Mode: MM2S and S2MM channels, register bank, interrupts, errors, soft reset | Done: verified with GHDL and QuestaSim, code coverage closed or justified |
| b | Scatter/Gather Mode: descriptor engine, cyclic mode, interrupt coalescing and delay, packets of several buffers, keyhole | Done: verified with GHDL and QuestaSim, code coverage closed or justified |
| c | Control and status streams (user application fields), micro mode | Open |
| d | Driver tests on hardware (bare-metal and Linux on a processor system) | Open |

## Modules

| Module | Blocks (architecture section 7) | Status |
| --- | --- | --- |
| `odma_pkg` | Common package; shared verification components (AXI memory model, sequence player) and the model of the programming sequences | Done |
| `odma_registers` | RG-1 to RG-4 (register interface) | Done, Scatter/Gather Mode included |
| `odma_mm2s` | MM-1 to MM-3 (MM2S channel) | MM-1, MM-2 done, with the join of packets of several buffers and keyhole; MM-3 in phase c |
| `odma_s2mm` | S2-1 to S2-3 (S2MM channel) | S2-1, S2-2 done, with the split of packets over several buffers, keyhole, the next buffer accepted while the write responses of the one before arrive, chunks that follow the buffer address in Scatter/Gather Mode and low-latency writes with equal widths; S2-3 in phase c |
| `odma_sg` | SG-1 to SG-3 (Scatter/Gather engine) | Done, integrated into the core |
| `odma_core` | CO-1 (core top level) | DR mode and SG mode done |

## Open items

| Item | State |
| --- | --- |
| S2MM in SG mode with short buffers and a write response latency | Open: the engine keeps a window of two descriptors per channel, so a buffer that fills faster than the write responses of the buffer before arrive waits at its end ([user guide](user_guide.md#7-performance)). A result queue of two transfers in the S2MM channel together with a window of three S2MM descriptors in the engine raises 512 / 256 bits with 4-beat bursts and 1 KB buffers at a write response latency of 50 clock cycles from 0.47 to 0.69 beats per clock cycle (measured). It needs a window generic per channel in the engine, a queue of issued descriptors of any depth with their statuses in order, a descriptor buffer of three entries for S2MM and an S2MM channel that accepts a third command before the first result |
