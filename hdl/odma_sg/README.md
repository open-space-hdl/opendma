# odma_sg

Scatter/Gather engine of OpenDMA (phase b): fetches the descriptors of each channel from memory through its own AXI4
master, turns every descriptor into a transfer command of its channel, writes the status of every processed
descriptor back and reports completed packets and errors to the register interface.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, interpretations of the published interface |
| [Architecture](docs/architecture.md) | Channel engines, descriptor port, descriptor buffer, state machines, timing |
| [Verification plan](docs/verification_plan.md) | Test cases, requirement coverage, functional coverage |

The module is in design: RTL, testbench and verification report follow.
