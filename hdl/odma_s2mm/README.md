# odma_s2mm

Stream to memory channel of OpenDMA: receives the S2MM stream into an ECC-protected data buffer, cuts each packet
into chunks of one memory burst and writes the complete chunks into the buffer of the transfer command through an
AXI4 write master, never beyond the buffer, and returns one result per command.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, interpretations of the published interface |
| [Architecture](docs/architecture.md) | Entities, ports, chunk former, write command, halt, flush and drain |
| [Verification plan](docs/verification_plan.md) | Test cases |

Tests: `python run.py "*odma_s2mm*"`
