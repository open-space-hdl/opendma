# OpenDMA Roadmap

This page tracks the development phases and the state of every module. A module is done when its verification report
is written and its regression is green.

## Technology readiness

The core is in development and has no technology readiness level yet. The
[TRL page](https://openspacehdl.org/trl/) explains what the levels mean for an IP core.

| Next level | What is needed | State |
| --- | --- | --- |
| TRL 3 | Every module of the phases below implemented and fully verified by simulation (GHDL and QuestaSim, code coverage closed), traceability matrix complete | Open |
| TRL 4 | Synthesis and timing closure on a target FPGA; hardware test with the drivers of a processor system; hardware test plan and test report | Open |

## Development phases

| Phase | Content | State |
| --- | --- | --- |
| a | Direct Register Mode: MM2S and S2MM channels, register bank, interrupts, errors, soft reset | Implemented, verified with GHDL; QuestaSim and code coverage open |
| b | Scatter/Gather Mode: descriptor engine, cyclic mode, interrupt coalescing and delay, packets of several buffers, keyhole | Implemented, verified with GHDL; QuestaSim and code coverage open |
| c | Control and status streams (user application fields), micro mode | Open |
| d | Driver tests on hardware (bare-metal and Linux on a processor system) | Open |

## Modules

| Module | Blocks (architecture section 7) | Status |
| --- | --- | --- |
| `odma_pkg` | Common package; shared verification components (AXI memory model, sequence player) and the model of the programming sequences | Done (GHDL) |
| `odma_registers` | RG-1 to RG-4 (register interface) | Done (GHDL), Scatter/Gather Mode included |
| `odma_mm2s` | MM-1 to MM-3 (MM2S channel) | MM-1, MM-2 done (GHDL), with the join of packets of several buffers and keyhole; MM-3 in phase c |
| `odma_s2mm` | S2-1 to S2-3 (S2MM channel) | S2-1, S2-2 done (GHDL), with the split of packets over several buffers and keyhole; S2-3 in phase c |
| `odma_sg` | SG-1 to SG-3 (Scatter/Gather engine) | Done (GHDL), integrated into the core |
| `odma_core` | CO-1 (core top level) | DR mode and SG mode done (GHDL) |

## Planned improvements

| Item | Content | State |
| --- | --- | --- |
| Pipelined S2MM commands | The S2MM channel takes the next buffer of a packet only after the write responses of the full one, so the stream pauses at every buffer boundary inside a packet and the write master runs empty (user guide, section 7). Taking the next command once the last write command of the full buffer is issued keeps the stream running: the first chunk of the next buffer is ready when the last burst ends, which removes the refill of the master and hides the write response latency. A depth of two needs one more set of command registers, logic under the TMR of the synthesis tool, and no further FT buffer | Planned (step 5) |
| Burst-aligned S2MM chunks | A chunk at a buffer address that is not a multiple of the memory word covers one memory word more than a burst and is written as two bursts. In Scatter/Gather Mode the split receives the buffer address before the data, so the first chunk of a buffer can end at the first burst boundary of the address: one extra burst per buffer instead of one per chunk | Planned (step 5) |
| Low-latency write commands | The write master starts a burst only when all its data is buffered, 26 clock cycles after the command with the defaults. S2MM forms every chunk completely before its command; when no gap between the write beats of a burst can occur, the low-latency mode of the master starts the burst with the command and removes most of that time, also inside a buffer | Under study (step 5) |
