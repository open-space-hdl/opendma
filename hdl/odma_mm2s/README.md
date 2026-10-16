# odma_mm2s

Memory to stream channel of OpenDMA: reads the buffer of each transfer command through an AXI4 read master with
unaligned addresses, burst and 4 KB splitting and an ECC-protected read data buffer, sends it on the MM2S stream with
`TKeep` and `TLast` and returns one result per command.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, interpretations of the published interface |
| [Architecture](docs/architecture.md) | Entities, ports, read command, stream output, halt and drain |
| [Verification plan](docs/verification_plan.md) | Test cases |

Tests: `python run.py "*odma_mm2s*"`
