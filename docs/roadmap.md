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
| Pipelined S2MM commands | The S2MM channel takes the next buffer of a packet only after the write responses of the full one, so the stream pauses at every buffer boundary inside a packet (user guide, section 7). A command queue removes the pause; it needs one more FT buffer (index 10 of the extension window). Planned together with the performance work on the ft AXI masters of open-logic-ft | Open |
