# odma_registers

Register interface of OpenDMA: the registers of both channels at the offsets of the AXI DMA product guide PG021
(Direct Register Mode), the transfer commands and results of the channels, the interrupt flags and outputs, the soft
reset with the reset outputs of the stream peers, and the extension window with identification, configuration
readback, ECC counters and error injection.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, interpretations of the published interface |
| [Architecture](docs/architecture.md) | Entities, ports, channel state machine, soft reset, extension window |
| [Verification plan](docs/verification_plan.md) | Test cases |

Tests: `python run.py "*odma_registers*"`
