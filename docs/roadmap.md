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
| a | Direct Register Mode: MM2S and S2MM channels, register bank, interrupts, errors, soft reset | Architecture in work |
| b | Scatter/Gather Mode: descriptor engine, cyclic mode, interrupt coalescing and delay, keyhole | Open |
| c | Control and status streams (user application fields), micro mode | Open |
| d | Driver tests on hardware (bare-metal and Linux on a processor system) | Open |
