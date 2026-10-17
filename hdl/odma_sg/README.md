# odma_sg

Scatter/Gather engine of OpenDMA (phase b): fetches the descriptors of each channel from memory through its own AXI4
master, turns every descriptor into a transfer command of its channel, writes the status of every processed
descriptor back and reports completed packets and errors to the register interface.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, interpretations of the published interface |
| [Architecture](docs/architecture.md) | Channel engines, descriptor port, descriptor buffer, state machines, timing |
| [Verification plan](docs/verification_plan.md) | Test cases, requirement coverage, functional coverage |
| [Verification report](docs/verification_report.md) | Results, descriptor rate, generic ranges, checks of the testbench |

Tests: `python run.py "*odma_sg*"`

| File | Content |
| --- | --- |
| `src/odma_sg.vhd` | Module top: the channel engines and the descriptor port |
| `src/odma_sg_channel.vhd` | Descriptor engine of one channel (SG-1, SG-2) with its descriptor buffer |
| `src/odma_sg_port.vhd` | Descriptor port (SG-3): arbiters and the AXI4 master |
| `tb/odma_sg_th.vhd` | Harness: clock, DUT, the AXI memory model on the descriptor port, a model of each channel, the monitors |
| `tb/odma_sg_tb.vhd` | VUnit testbench, one `run("test_...")` per test case of the verification plan |
| `tb/odma_sg_tb_pkg.vhd` | Register side, behaviour of the channel models and the observations of the harness |
| `tb/vunit_config.py` | VUnit configurations of the generics (verification plan, section 2) |
