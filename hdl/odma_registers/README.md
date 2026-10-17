# odma_registers

Register interface of OpenDMA: the registers of both channels at the offsets of the AXI DMA product guide PG021
(Direct Register Mode and Scatter/Gather Mode), the transfer commands and results of the channels in Direct Register
Mode, the control interface of the descriptor engines in Scatter/Gather Mode, the interrupt flags, the interrupt
threshold and delay timer and the interrupt outputs, the soft reset with the reset outputs of the stream peers, and
the extension window with identification, configuration readback, ECC counters and error injection.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, interpretations of the published interface |
| [Architecture](docs/architecture.md) | Entities, ports, channel state machines, interrupt controller, soft reset, extension window |
| [Register map](docs/register_map.md) | Registers and fields (generated from `regs/odma_regs.yml`) |
| [Verification plan](docs/verification_plan.md) | Test cases |
| [Verification report](docs/verification_report.md) | Results, generic ranges |

Tests: `python run.py "*odma_registers*"`

| File | Content |
| --- | --- |
| `tb/odma_registers_th.vhd` | Harness: clock, DUT, AXI4-Lite VVC on the register port, a model of each channel on the command, result and control ports, a model of each descriptor engine on the Scatter/Gather ports |
| `tb/odma_registers_tb.vhd` | VUnit testbench, one `run("test_...")` per test case of the verification plan |
| `tb/odma_registers_tb_pkg.vhd` | Configuration of the channel models, the signals of the engine models and the observations of the harness |
| `tb/vunit_config.py` | VUnit configurations of the generics (verification plan, section 2) |
