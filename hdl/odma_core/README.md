# odma_core

Top level of OpenDMA: the register interface `odma_registers`, the channels `odma_mm2s` and `odma_s2mm` and, with
`IncludeSg_g`, the Scatter/Gather engine `odma_sg` of the configuration, connected through the transfer command,
transfer result, channel control, descriptor engine control and ECC interfaces, with the idle values of a port that
the configuration does not include, the packet start detector of the delay timer and the consistency checks of the
generics.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements of the assembled core |
| [Architecture](docs/architecture.md) | Entities, ports, connections, DR and SG mode, FT buffer indices, packet start detector, excluded ports, consistency checks |
| [Verification plan](docs/verification_plan.md) | Test cases |
| [Verification report](docs/verification_report.md) | Results, generic ranges |

Tests: `python run.py "*odma_core*"`; synthesis check of the generics: `python run.py --compile`, then
`python lint/synth_check.py`

| File | Content |
| --- | --- |
| `tb/odma_core_th.vhd` | Harness: clock, reset, DUT, AXI4-Lite VVC, one AXI memory model per memory port (also the descriptor port), AXI4-Stream VVCs, a resettable S2MM stream peer, monitors of the AXI4 transactions, of the S2MM beats during a soft reset and of the idle values of an excluded channel and of the descriptor port in DR mode |
| `tb/odma_core_tb.vhd` | VUnit testbench, one `run("test_...")` per test case of the verification plan |
| `tb/odma_core_tb_pkg.vhd` | Memory model instances and the observations of the harness |
| `tb/vunit_config.py` | VUnit configurations per test and the `pre_config` that writes the model scenarios (verification plan, section 2) |
